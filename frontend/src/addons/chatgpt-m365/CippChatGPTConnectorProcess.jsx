import { useEffect, useRef, useState } from 'react'
import {
  Alert,
  Box,
  Button,
  Chip,
  CircularProgress,
  Divider,
  List,
  ListItem,
  ListItemIcon,
  ListItemText,
  Stack,
  Step,
  StepContent,
  StepLabel,
  Stepper,
  Typography,
} from '@mui/material'
import {
  CheckCircle,
  Info as InfoIcon,
  RadioButtonUnchecked,
  Refresh,
  Warning as WarningIcon,
} from '@mui/icons-material'
import { useForm, useWatch } from 'react-hook-form'
import { ApiGetCall, ApiPostCall } from '../../api/ApiCall'
import { CippFormComponent } from '../../components/CippComponents/CippFormComponent'
import { CippFormUserSelector } from '../../components/CippComponents/CippFormUserSelector'
import { CippAddonStepResults } from '../../components/CippAddons/CippAddonStepResults'
import { CippChatGPTCustomerInfo } from './CippChatGPTCustomerInfo'
import { CippChatGPTAccessStep } from './CippChatGPTAccessStep'
import {
  CippAddonPdfCard,
  addonPdfFileName,
} from '../../components/CippAddons/CippAddonPdfCard'
import { CippAddonGuideUpload } from '../../components/CippAddons/CippAddonGuideUpload'

export const DEFAULT_GROUP = 'SG-ChatGPT-Users'

/** The ChatGPT app's entry in ListChatGPTConnector's status. */
const chatgptApp = (status) =>
  (status?.Apps ?? []).find((a) => a.Key === 'ChatGPT')

/**
 * People who can use ChatGPT now, as user-picker values: the access group's members, or the people
 * assigned to the app directly.
 * @param {object} status
 */
export const chatgptCurrentUsers = (status) => {
  if (status?.Group?.Exists && (status.Group.Members ?? []).length > 0) {
    return status.Group.Members.map((m) => ({
      value: m.Id,
      label: m.Upn ? `${m.Name} (${m.Upn})` : m.Name,
    }))
  }
  return (chatgptApp(status)?.Assigned ?? [])
    .filter((a) => a.Type === 'User')
    .map((a) => ({ value: a.PrincipalId, label: a.Name }))
}

/**
 * Which of the steps are done, from ListChatGPTConnector's status. Unlike Claude there is no consent
 * page step: CIPP gives admin consent itself when access is saved, for exactly the chosen level.
 * @param {object} status
 */
export const chatgptConnectorProgress = (status) => {
  const apps = Array.isArray(status?.Apps) ? status.Apps : []
  const added = apps.length > 0 && apps.every((a) => a.Exists)
  const consented = added && apps.every((a) => a.Consented)
  const restricted =
    added &&
    apps.every((a) => a.AssignmentRequired && (a.Assigned?.length ?? 0) > 0)
  const locked =
    status?.UserConsent?.Allowed === false &&
    status?.AdminConsentRequests?.Enabled === true
  const level = status?.Access?.Level
  const accessSet =
    consented && Boolean(level) && !['full', 'custom'].includes(level)
  const active = !added ? 0 : !restricted ? 1 : !accessSet ? 2 : 3
  return { added, consented, restricted, locked, accessSet, active }
}

/**
 * The request body for ExecChatGPTConnector's Apply action, from the form.
 * @param {string} tenant
 * @param {object} values
 */
export const chatgptConnectorApplyBody = (tenant, values) => ({
  tenantFilter: tenant,
  Action: 'Apply',
  Users: (values.users ?? []).map((u) => u?.value ?? u).filter(Boolean),
  GroupName: (values.groupName ?? '').trim() || DEFAULT_GROUP,
  AssignUsersDirectly: Boolean(values.assignDirect),
  LockUserConsent: Boolean(values.lockConsent),
  RemoveOtherDirect: Boolean(values.removeOtherDirect),
})

const Tick = ({ ok, children }) => (
  <ListItem disableGutters sx={{ py: 0.25 }}>
    <ListItemIcon sx={{ minWidth: 32 }}>
      {ok === true ? (
        <CheckCircle color="success" fontSize="small" />
      ) : ok === false ? (
        <RadioButtonUnchecked color="disabled" fontSize="small" />
      ) : ok === 'warn' ? (
        <WarningIcon color="warning" fontSize="small" />
      ) : (
        <InfoIcon color="info" fontSize="small" />
      )}
    </ListItemIcon>
    <ListItemText primary={children} />
  </ListItem>
)

/**
 * Community Additions > ChatGPT for Microsoft 365 (add-on chatgpt-m365).
 * Add OpenAI's ChatGPT app, limit it to chosen people, give admin consent for exactly the chosen
 * access level, then match the actions in ChatGPT's own admin console.
 */
export const CippChatGPTConnectorProcess = ({ tenant }) => {
  const formControl = useForm({
    mode: 'onChange',
    defaultValues: {
      users: [],
      groupName: DEFAULT_GROUP,
      assignDirect: false,
      lockConsent: true,
      removeOtherDirect: false,
    },
  })
  const values = useWatch({ control: formControl.control })
  const [statusGroup, setStatusGroup] = useState(DEFAULT_GROUP)
  const [includeGuide, setIncludeGuide] = useState(true)
  const usersLoadedFor = useRef(null)
  const validTenant = Boolean(tenant) && tenant !== 'AllTenants'

  const status = ApiGetCall({
    url: '/api/ListChatGPTConnector',
    data: { tenantFilter: tenant, GroupName: statusGroup },
    queryKey: `ChatGPTConnector-${tenant}-${statusGroup}`,
    waiting: validTenant,
    staleTime: 0,
    retry: 1,
  })
  const addApps = ApiPostCall({
    relatedQueryKeys: [`ChatGPTConnector-${tenant}-*`],
  })
  const apply = ApiPostCall({
    relatedQueryKeys: [`ChatGPTConnector-${tenant}-*`],
  })

  const s = status.data
  const progress = chatgptConnectorProgress(s)
  const app = chatgptApp(s)

  // Suggest direct assignment when the tenant has no Entra ID P1.
  useEffect(() => {
    if (s?.EntraP1 === false) formControl.setValue('assignDirect', true)
  }, [s?.EntraP1]) // eslint-disable-line react-hooks/exhaustive-deps

  // Start the people list from who can use ChatGPT now, once per tenant.
  useEffect(() => {
    if (!s || usersLoadedFor.current === tenant) return
    usersLoadedFor.current = tenant
    const current = chatgptCurrentUsers(s)
    if (
      current.length > 0 &&
      (formControl.getValues('users') ?? []).length === 0
    ) {
      formControl.setValue('users', current)
    }
    if (
      s.Group?.Exists === false &&
      s.AssignedByGroup === false &&
      current.length > 0
    ) {
      formControl.setValue('assignDirect', true)
    }
  }, [s, tenant]) // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    addApps.reset()
    apply.reset()
  }, [tenant]) // eslint-disable-line react-hooks/exhaustive-deps

  if (!validTenant) {
    return (
      <Alert severity="info">
        Choose a tenant with the tenant selector at the top of the page.
      </Alert>
    )
  }

  const runApply = () => {
    const body = chatgptConnectorApplyBody(tenant, values)
    setStatusGroup(body.GroupName)
    apply.mutate({ url: '/api/ExecChatGPTConnector', data: body })
  }

  const usersChosen = (values.users ?? []).length > 0

  const levels = s?.Options?.Levels ?? []
  const levelName = (id) => {
    const l = levels.find((x) => x.id === id)
    return l ? `Level ${l.number}: ${l.name}` : null
  }
  const areaNames = (ids) =>
    (s?.Options?.ReadAreas ?? [])
      .filter((a) => (ids ?? []).includes(a.id))
      .map((a) => a.noun)
  const everyoneLevel = levels.find((l) => l.id === s?.Access?.Level)
  const selfApproved = (s?.Access?.People ?? []).filter((p) => p.SelfApproved)
  const otherGrants = app?.OtherGrants ?? []

  return (
    <Stack spacing={3}>
      <CippChatGPTCustomerInfo
        tenant={tenant}
        tenantName={s?.Tenant}
        readiness={s?.Readiness}
        loading={status.isLoading}
      />

      <Typography color="text.secondary">
        Sets up OpenAI's ChatGPT apps for Microsoft 365 (Outlook, Teams and
        SharePoint) in <strong>{s?.Tenant ?? tenant}</strong> so that only the
        people you choose can use them, with only the access you choose. Each
        step checks what's already there, so it's safe to run again.
      </Typography>

      <Box>
        <Stack direction="row" alignItems="center" spacing={1} sx={{ mb: 1 }}>
          <Typography variant="h6">Current setup</Typography>
          <Button
            size="small"
            startIcon={
              status.isFetching ? <CircularProgress size={14} /> : <Refresh />
            }
            onClick={() => {
              setStatusGroup((values.groupName ?? '').trim() || DEFAULT_GROUP)
              status.refetch()
            }}
            disabled={status.isFetching}
          >
            Check again
          </Button>
        </Stack>
        {status.isError && (
          <Alert severity="error">
            {String(
              status.error?.response?.data?.Results ?? status.error?.message
            )}
          </Alert>
        )}
        {status.isLoading && <CircularProgress size={24} />}
        {s && (
          <List dense disablePadding aria-label="Current setup">
            {(s.Apps ?? []).map((a) => (
              <Tick
                key={a.Key}
                ok={a.Exists && a.Consented && a.AssignmentRequired}
              >
                <strong>{a.Name}</strong> (OpenAI):{' '}
                {!a.Exists
                  ? 'not in the tenant'
                  : [
                      a.Consented
                        ? 'admin consent given'
                        : 'no admin consent yet',
                      a.AssignmentRequired
                        ? 'assignment required'
                        : 'anyone can use it',
                      `${a.Assigned?.length ?? 0} assigned`,
                    ].join(', ')}
                {a.Error ? ` (couldn't read: ${a.Error})` : ''}
              </Tick>
            ))}
            <Tick ok={s.Group?.Exists ? true : false}>
              Group <strong>{s.Group?.Name}</strong>:{' '}
              {s.Group?.Exists
                ? `${s.Group.Members?.length ?? 0} member${s.Group.Members?.length === 1 ? '' : 's'}${
                    s.Group.Members?.length
                      ? ` (${s.Group.Members.map((m) => m.Upn ?? m.Name).join(', ')})`
                      : ''
                  }${s.AssignedByGroup ? ', assigned to ChatGPT' : ''}`
                : "doesn't exist yet"}
            </Tick>
            <Tick ok={s.UserConsent?.Allowed === false}>
              {s.UserConsent?.Allowed === false
                ? s.UserConsent?.ManagedByCipp
                  ? "Users can't approve apps themselves (CIPP's consent standard)"
                  : "Users can't approve apps themselves"
                : s.UserConsent?.Allowed
                  ? 'Users can approve apps themselves'
                  : "Couldn't read user consent settings"}
            </Tick>
            <Tick ok={Boolean(s.AdminConsentRequests?.Enabled)}>
              {s.AdminConsentRequests?.Enabled
                ? `Admin consent requests on${
                    s.AdminConsentRequests.GlobalAdminsReview
                      ? ', Global Administrators review'
                      : ''
                  }`
                : 'Admin consent requests off'}
            </Tick>
            {s.Access && (s.Access.TenantScopes ?? []).length > 0 && (
              <Tick ok={!['full', 'custom'].includes(s.Access.Level)}>
                Everyone:{' '}
                <strong>
                  {levelName(s.Access.Level) ?? 'a custom set of permissions'}
                </strong>
                {`, reading ${areaNames(s.Access.ReadAreas).join(', ') || 'nothing'}`}
                {(s.Access.People ?? []).filter((p) => !p.SelfApproved)
                  .length > 0 &&
                  `. Own level: ${s.Access.People.filter((p) => !p.SelfApproved)
                    .map(
                      (p) =>
                        `${p.Upn ?? p.Name} (${levelName(p.Level) ?? 'custom'})`
                    )
                    .join(', ')}`}
              </Tick>
            )}
            {selfApproved.length > 0 && (
              <Tick ok="warn">
                Approved ChatGPT for themselves:{' '}
                {selfApproved.map((p) => p.Upn ?? p.Name).join(', ')}. These
                grants were made before users were stopped from approving apps.
                Saving step 3 removes them.
              </Tick>
            )}
            {otherGrants.length > 0 && (
              <Tick ok="warn">
                Other permissions ChatGPT holds:{' '}
                {otherGrants
                  .map(
                    (g) =>
                      `${g.Resource} (${g.Scopes.join(', ')}${g.User ? `, approved by ${g.User}` : ', everyone'})`
                  )
                  .join('; ')}
                . The levels don't change these; remove them in Entra
                (Enterprise apps &gt; ChatGPT &gt; Permissions) if they aren't
                wanted.
              </Tick>
            )}
            <Tick ok={null}>
              Entra ID P1:{' '}
              {s.EntraP1 === true
                ? 'yes, so a group can be assigned'
                : s.EntraP1 === false
                  ? 'no, so people are assigned one by one'
                  : 'unknown'}
            </Tick>
          </List>
        )}
      </Box>

      <Divider />

      <Stepper orientation="vertical" activeStep={progress.active} nonLinear>
        <Step completed={progress.added} expanded>
          <StepLabel>Add the ChatGPT app to the tenant</StepLabel>
          <StepContent>
            <Typography variant="body2" color="text.secondary">
              Adds OpenAI's <em>ChatGPT</em> app (verified publisher OpenAI,
              L.L.C.). One app is used by all of ChatGPT's Microsoft apps:
              Outlook Email, Outlook Calendar, Teams and SharePoint. Adding it
              gives it no access yet.
            </Typography>
            <Button
              sx={{ mt: 1.5 }}
              variant={progress.added ? 'outlined' : 'contained'}
              disabled={!s || addApps.isPending}
              onClick={() =>
                addApps.mutate({
                  url: '/api/ExecChatGPTConnector',
                  data: { tenantFilter: tenant, Action: 'AddApps' },
                })
              }
            >
              {progress.added ? 'Check the app again' : 'Add the ChatGPT app'}
            </Button>
            <CippAddonStepResults action={addApps} />
          </StepContent>
        </Step>

        <Step completed={progress.restricted} expanded>
          <StepLabel>Choose who can use ChatGPT</StepLabel>
          <StepContent>
            <Stack spacing={2} sx={{ maxWidth: 640 }}>
              <CippFormUserSelector
                formControl={formControl}
                name="users"
                label="People who can use ChatGPT with Microsoft 365"
                multiple={true}
                showRefresh={true}
              />
              <CippFormComponent
                type="textField"
                name="groupName"
                label="Access group"
                formControl={formControl}
                disabled={Boolean(values.assignDirect)}
                helperText="Security group to create or reuse. Its members can use ChatGPT."
              />
              <CippFormComponent
                type="switch"
                name="assignDirect"
                label="Assign people directly instead of using a group (for tenants without Entra ID P1)"
                formControl={formControl}
              />
              <CippFormComponent
                type="switch"
                name="lockConsent"
                label="Also stop users approving apps themselves and turn on admin consent requests (Global Administrators review)"
                formControl={formControl}
              />
              {!values.assignDirect && (
                <CippFormComponent
                  type="switch"
                  name="removeOtherDirect"
                  label="Remove anyone assigned directly who isn't in the group"
                  formControl={formControl}
                />
              )}
              <Box>
                <Button
                  variant="contained"
                  disabled={!progress.added || !usersChosen || apply.isPending}
                  onClick={runApply}
                >
                  {progress.restricted ? 'Apply again' : 'Apply'}
                </Button>
                {!progress.added && (
                  <Typography variant="body2" sx={{ mt: 1 }}>
                    Add the ChatGPT app first.
                  </Typography>
                )}
              </Box>
            </Stack>
            <CippAddonStepResults action={apply} />
          </StepContent>
        </Step>

        <Step completed={progress.accessSet} expanded>
          <StepLabel>Choose what ChatGPT can read and change</StepLabel>
          <StepContent>
            <CippChatGPTAccessStep
              tenant={tenant}
              status={s}
              disabled={!progress.added}
            />
          </StepContent>
        </Step>

        <Step completed={false} expanded>
          <StepLabel optional={<Chip size="small" label="By hand" />}>
            Match it in ChatGPT
          </StepLabel>
          <StepContent>
            <Box component="ul" sx={{ pl: 2.5, my: 0 }}>
              <Typography component="li" variant="body2">
                In ChatGPT, as a workspace owner or admin of the customer's
                Business, Enterprise or Edu workspace: Admin console &gt; Plugins
                (Apps in older workspaces). Turn on Outlook Email, Outlook Calendar, Teams and
                SharePoint as wanted.
              </Typography>
              <Typography component="li" variant="body2">
                Turn off the actions above the level you chose.{' '}
                {everyoneLevel ? (
                  <>
                    For <strong>Level {everyoneLevel.number}</strong>:{' '}
                    {everyoneLevel.chatgptActions}
                  </>
                ) : (
                  'Choose a level in the step above first.'
                )}{' '}
                ChatGPT asks for the permissions of every action that is on;
                if one isn't granted, people see &quot;Need admin
                approval&quot;.
              </Typography>
              <Typography component="li" variant="body2">
                Set the apps&apos; action permission to <em>Allow read
                actions</em> (or <em>Always ask</em>) so ChatGPT asks before
                it sends or changes anything.
              </Typography>
              <Typography component="li" variant="body2">
                Higher levels for named people need ChatGPT Enterprise or Edu:
                give them a role that has the extra actions on. On ChatGPT
                Business, actions are the same for everyone.
              </Typography>
              <Typography component="li" variant="body2">
                Don&apos;t run ChatGPT&apos;s <em>Review permissions in
                Microsoft Entra</em> with more actions on than the level
                allows: it grants every permission those actions need. If
                someone does, save the step above again.
              </Typography>
              <Typography component="li" variant="body2">
                If the tenant uses Conditional Access, include the ChatGPT app
                in its MFA policy.
              </Typography>
            </Box>
          </StepContent>
        </Step>
      </Stepper>

      <CippAddonPdfCard
        url="/api/ExecChatGPTConnectorSummaryPdf"
        body={{
          tenantFilter: tenant,
          GroupName: statusGroup,
          IncludeGuide: Boolean(s?.Guide) && includeGuide,
        }}
        title="Summary for the customer"
        description="A branded PDF to send when setup is done, read from the tenant as it is now: who can use ChatGPT and at what level, what ChatGPT can read, the safeguards in place, anything not finished, and what they do next."
        dialogTitle="ChatGPT for Microsoft 365: setup summary"
        fileName={addonPdfFileName(
          'ChatGPT_setup_summary',
          s?.Tenant ?? tenant
        )}
      >
        <CippAddonGuideUpload
          addonId="chatgpt-m365"
          guideKey="connection"
          title="Connection guide"
          description="Your own step-by-step guide (a Word document), added to the end of the summary in the same style. It is kept in this CIPP instance and used for every customer."
          guide={s?.Guide}
          include={includeGuide}
          onIncludeChange={setIncludeGuide}
          includeLabel="Add the connection guide to the end of the summary"
          relatedQueryKeys={[`ChatGPTConnector-${tenant}-*`]}
        />
      </CippAddonPdfCard>
    </Stack>
  )
}

export default CippChatGPTConnectorProcess
