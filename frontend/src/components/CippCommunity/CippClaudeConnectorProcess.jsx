import { useEffect, useRef, useState } from 'react'
import {
  Alert,
  Box,
  Button,
  Chip,
  CircularProgress,
  Divider,
  Link,
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
  OpenInNew,
  RadioButtonUnchecked,
  Refresh,
} from '@mui/icons-material'
import { useForm, useWatch } from 'react-hook-form'
import { ApiGetCall, ApiPostCall } from '../../api/ApiCall'
import { CippFormComponent } from '../CippComponents/CippFormComponent'
import { CippFormUserSelector } from '../CippComponents/CippFormUserSelector'
import { CippClaudeStepResults } from './CippClaudeStepResults'
import { CippClaudeCustomerInfo } from './CippClaudeCustomerInfo'
import { CippClaudeAccessStep } from './CippClaudeAccessStep'

export const DEFAULT_GROUP = 'SG-Claude-Users'
const POLL_MS = 5000
const POLL_FOR_MS = 5 * 60 * 1000

/**
 * People who can use Claude now, as user-picker values: the access group's members, or the people
 * assigned to the apps directly.
 * @param {object} status
 */
export const claudeCurrentUsers = (status) => {
  if (status?.Group?.Exists && (status.Group.Members ?? []).length > 0) {
    return status.Group.Members.map((m) => ({
      value: m.Id,
      label: m.Upn ? `${m.Name} (${m.Upn})` : m.Name,
    }))
  }
  const server = (status?.Apps ?? []).find((a) => a.Key === 'Server')
  return (server?.Assigned ?? [])
    .filter((a) => a.Type === 'User')
    .map((a) => ({ value: a.PrincipalId, label: a.Name }))
}

/**
 * Which of the steps are done, from ListClaudeConnector's status.
 * @param {object} status
 */
export const claudeConnectorProgress = (status) => {
  const apps = Array.isArray(status?.Apps) ? status.Apps : []
  const added = apps.length > 0 && apps.every((a) => a.Exists)
  const consented = added && apps.every((a) => a.Consented)
  const restricted =
    consented &&
    apps.every((a) => a.AssignmentRequired && (a.Assigned?.length ?? 0) > 0)
  const locked =
    status?.UserConsent?.Allowed === false &&
    status?.AdminConsentRequests?.Enabled === true
  const level = status?.Access?.Level
  const accessSet =
    consented && Boolean(level) && !['full', 'custom'].includes(level)
  const active = !added
    ? 0
    : !consented
      ? 1
      : !restricted
        ? 2
        : !accessSet
          ? 3
          : 4
  return { added, consented, restricted, locked, accessSet, active }
}

/**
 * The request body for ExecClaudeConnector's Apply action, from the form.
 * @param {string} tenant
 * @param {object} values
 */
export const claudeConnectorApplyBody = (tenant, values) => ({
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
      ) : (
        <InfoIcon color="info" fontSize="small" />
      )}
    </ListItemIcon>
    <ListItemText primary={children} />
  </ListItem>
)

/**
 * Community Additions > Standard Processes > Claude for Microsoft 365.
 * The CIPP version of Set-ClaudeM365Connector.ps1: add the apps, a Global Admin approves consent,
 * then limit Claude to chosen people (and optionally lock down user consent).
 */
export const CippClaudeConnectorProcess = ({ tenant }) => {
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
  const [pollUntil, setPollUntil] = useState(0)
  const usersLoadedFor = useRef(null)
  const validTenant = Boolean(tenant) && tenant !== 'AllTenants'

  const status = ApiGetCall({
    url: '/api/ListClaudeConnector',
    data: { tenantFilter: tenant, GroupName: statusGroup },
    queryKey: `ClaudeConnector-${tenant}-${statusGroup}`,
    waiting: validTenant,
    staleTime: 0,
    retry: 1,
    refetchInterval: pollUntil > 0 ? POLL_MS : false,
  })
  const addApps = ApiPostCall({
    relatedQueryKeys: [`ClaudeConnector-${tenant}-*`],
  })
  const apply = ApiPostCall({
    relatedQueryKeys: [`ClaudeConnector-${tenant}-*`],
  })

  const s = status.data
  const progress = claudeConnectorProgress(s)

  // Stop checking for consent once both apps have it, or after five minutes.
  useEffect(() => {
    if (pollUntil === 0) return
    if (progress.consented || Date.now() > pollUntil) setPollUntil(0)
  }, [pollUntil, progress.consented, status.dataUpdatedAt])

  // Suggest direct assignment when the tenant has no Entra ID P1.
  useEffect(() => {
    if (s?.EntraP1 === false) formControl.setValue('assignDirect', true)
  }, [s?.EntraP1]) // eslint-disable-line react-hooks/exhaustive-deps

  // Start the people list from who can use Claude now, once per tenant.
  useEffect(() => {
    if (!s || usersLoadedFor.current === tenant) return
    usersLoadedFor.current = tenant
    const current = claudeCurrentUsers(s)
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
    setPollUntil(0)
  }, [tenant]) // eslint-disable-line react-hooks/exhaustive-deps

  if (!validTenant) {
    return (
      <Alert severity="info">
        Choose a tenant with the tenant selector at the top of the page.
      </Alert>
    )
  }

  const openConsent = (app) => {
    window.open(
      app.ConsentUrl,
      `consent-${app.Key}`,
      'popup,width=640,height=760'
    )
    setPollUntil(Date.now() + POLL_FOR_MS)
  }

  const runApply = () => {
    const body = claudeConnectorApplyBody(tenant, values)
    setStatusGroup(body.GroupName)
    apply.mutate({ url: '/api/ExecClaudeConnector', data: body })
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

  return (
    <Stack spacing={3}>
      <CippClaudeCustomerInfo
        tenant={tenant}
        tenantName={s?.Tenant}
        readiness={s?.Readiness}
        loading={status.isLoading}
      />

      <Typography color="text.secondary">
        Sets up Anthropic's Claude connector for Microsoft 365 in{' '}
        <strong>{s?.Tenant ?? tenant}</strong> so that only the people you
        choose can use it. Each step checks what's already there, so it's safe
        to run again.
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
                <strong>{a.Name}</strong>:{' '}
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
                  }${s.AssignedByGroup ? ', assigned to Claude' : ''}`
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
                {(s.Access.People ?? []).length > 0 &&
                  `. Own level: ${s.Access.People.map((p) => `${p.Upn ?? p.Name} (${levelName(p.Level) ?? 'custom'})`).join(', ')}`}
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
          <StepLabel>Add the Claude apps to the tenant</StepLabel>
          <StepContent>
            <Typography variant="body2" color="text.secondary">
              Adds <em>M365 MCP Client for Claude</em> and{' '}
              <em>M365 MCP Server for Claude</em>. Both need to be there before
              Microsoft's consent page will work.
            </Typography>
            <Button
              sx={{ mt: 1.5 }}
              variant={progress.added ? 'outlined' : 'contained'}
              disabled={!s || addApps.isPending}
              onClick={() =>
                addApps.mutate({
                  url: '/api/ExecClaudeConnector',
                  data: { tenantFilter: tenant, Action: 'AddApps' },
                })
              }
            >
              {progress.added ? 'Check the apps again' : 'Add the Claude apps'}
            </Button>
            <CippClaudeStepResults action={addApps} />
          </StepContent>
        </Step>

        <Step completed={progress.consented} expanded>
          <StepLabel>Approve Microsoft's consent page</StepLabel>
          <StepContent>
            <Typography variant="body2" color="text.secondary">
              Each button opens Microsoft's consent page in a pop-up. Sign in as
              a <strong>Global Administrator of {s?.Tenant ?? tenant}</strong>{' '}
              and choose Accept. Approve the client, then the server. This page
              checks every few seconds and ticks each one off when Microsoft has
              recorded it.
            </Typography>
            <Stack
              direction={{ xs: 'column', sm: 'row' }}
              spacing={1.5}
              sx={{ mt: 1.5 }}
            >
              {(s?.Apps ?? []).map((a) => (
                <Button
                  key={a.Key}
                  variant={a.Consented ? 'outlined' : 'contained'}
                  color={a.Consented ? 'success' : 'primary'}
                  disabled={!a.Exists}
                  startIcon={a.Consented ? <CheckCircle /> : <OpenInNew />}
                  onClick={() => openConsent(a)}
                >
                  {a.Consented
                    ? `${a.Key}: consent given`
                    : `Approve ${a.Name}`}
                </Button>
              ))}
            </Stack>
            {!progress.added && (
              <Typography variant="body2" sx={{ mt: 1 }}>
                Add the Claude apps first.
              </Typography>
            )}
            {pollUntil > 0 && !progress.consented && (
              <Stack
                direction="row"
                spacing={1}
                alignItems="center"
                sx={{ mt: 1.5 }}
              >
                <CircularProgress size={16} />
                <Typography variant="body2">
                  Waiting for Microsoft to record the consent…
                </Typography>
              </Stack>
            )}
            <Typography
              variant="caption"
              color="text.secondary"
              component="p"
              sx={{ mt: 1 }}
            >
              After you choose Accept, Microsoft moves the pop-up on to another
              page; you can close it then. If the pop-up is blocked, allow
              pop-ups for CIPP or copy the link:{' '}
              {(s?.Apps ?? []).map((a, i) => (
                <span key={a.Key}>
                  {i > 0 && ', '}
                  <Link
                    href={a.ConsentUrl}
                    target="_blank"
                    rel="noopener noreferrer"
                  >
                    {a.Key.toLowerCase()} consent link
                  </Link>
                </span>
              ))}
            </Typography>
          </StepContent>
        </Step>

        <Step completed={progress.restricted} expanded>
          <StepLabel>Choose who can use Claude</StepLabel>
          <StepContent>
            <Stack spacing={2} sx={{ maxWidth: 640 }}>
              <CippFormUserSelector
                formControl={formControl}
                name="users"
                label="People who can use Claude"
                multiple={true}
                showRefresh={true}
              />
              <CippFormComponent
                type="textField"
                name="groupName"
                label="Access group"
                formControl={formControl}
                disabled={Boolean(values.assignDirect)}
                helperText="Security group to create or reuse. Its members can use Claude."
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
                  disabled={
                    !progress.consented || !usersChosen || apply.isPending
                  }
                  onClick={runApply}
                >
                  {progress.restricted ? 'Apply again' : 'Apply'}
                </Button>
                {!progress.consented && (
                  <Typography variant="body2" sx={{ mt: 1 }}>
                    Both apps need admin consent first.
                  </Typography>
                )}
              </Box>
            </Stack>
            <CippClaudeStepResults action={apply} />
          </StepContent>
        </Step>

        <Step completed={progress.accessSet} expanded>
          <StepLabel>Choose what Claude can read and change</StepLabel>
          <StepContent>
            <CippClaudeAccessStep
              tenant={tenant}
              status={s}
              disabled={!progress.consented}
            />
          </StepContent>
        </Step>

        <Step completed={false} expanded>
          <StepLabel optional={<Chip size="small" label="By hand" />}>
            Finish in Claude
          </StepLabel>
          <StepContent>
            <Box component="ul" sx={{ pl: 2.5, my: 0 }}>
              <Typography component="li" variant="body2">
                In Claude, as an owner of the customer's Team or Enterprise
                organisation: Organisation settings &gt; Connectors &gt; add
                Microsoft 365.
              </Typography>
              <Typography component="li" variant="body2">
                If the tenant uses Conditional Access, include the two Claude
                apps in its MFA policy.
              </Typography>
              <Typography component="li" variant="body2">
                Optional, for the Claude desktop app: hide write tools on some
                devices with the managed configuration&apos;s toolPolicy.
              </Typography>
            </Box>
          </StepContent>
        </Step>
      </Stepper>
    </Stack>
  )
}

export default CippClaudeConnectorProcess
