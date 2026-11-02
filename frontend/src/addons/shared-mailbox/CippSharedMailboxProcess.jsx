import { useEffect, useRef, useState } from 'react'
import {
  Accordion,
  AccordionDetails,
  AccordionSummary,
  Alert,
  Box,
  Button,
  Card,
  CardContent,
  Skeleton,
  Stack,
  TextField,
  ToggleButton,
  ToggleButtonGroup,
  Typography,
} from '@mui/material'
import { ExpandMore } from '@mui/icons-material'
import { useForm, useWatch } from 'react-hook-form'
import { ApiGetCall, ApiPostCall } from '../../api/ApiCall'
import { CippFormComponent } from '../../components/CippComponents/CippFormComponent'
import { CippFormUserSelector } from '../../components/CippComponents/CippFormUserSelector'
import { CippFormDomainSelector } from '../../components/CippComponents/CippFormDomainSelector'
import {
  CippAddonPdfCard,
  addonPdfFileName,
} from '../../components/CippAddons/CippAddonPdfCard'
import { CippAddonStepResults } from '../../components/CippAddons/CippAddonStepResults'
import { CippAddonGuideUpload } from '../../components/CippAddons/CippAddonGuideUpload'
import { CippSharedMailboxChoices } from './CippSharedMailboxChoices'
import {
  answersFromStatus,
  defaultAnswers,
  peopleFromStatus,
  sharedMailboxSetupBody,
  sharedMailboxSetupProblem,
} from './sharedMailboxForm'

/** Sets each answer as its own field, so every radio group's controller sees the change. */
const setAnswers = (formControl, answers) =>
  Object.entries(answers).forEach(([key, value]) =>
    formControl.setValue(`answers.${key}`, value)
  )

const Section = ({ number, title, description, children }) => (
  <Card variant="outlined">
    <CardContent>
      <Typography variant="h6">
        {number}. {title}
      </Typography>
      {description && (
        <Typography
          variant="body2"
          color="text.secondary"
          sx={{ mt: 0.5, mb: 2 }}
        >
          {description}
        </Typography>
      )}
      {children}
    </CardContent>
  </Card>
)

/** What an existing mailbox has now: access, sending and the settings the page offers. */
const CurrentSetup = ({ status }) => {
  if (!status?.Exists) return null
  const names = (list) => (list ?? []).map((p) => p.Name).join(', ') || 'Nobody'
  const rows = [
    [
      'Full Access',
      status.Group
        ? `Group ${status.Group.Name}: ${names(status.Group.Members)}`
        : names(status.FullAccess),
    ],
    ['Send As', names(status.SendAs)],
    ['Send on behalf', names(status.SendOnBehalf)],
    ['Sent emails copied to it', status.MessageCopySentAs ? 'Yes' : 'No'],
    ['Address book', status.Hidden ? 'Hidden' : 'Shown'],
    ['Who can email it', status.InternalOnly ? 'Only the business' : 'Anyone'],
    ['Signature rule', status.SignatureRule ? 'Yes' : 'No'],
    [
      'Sign-in',
      status.SignInBlocked
        ? 'Blocked'
        : status.SignInBlocked === false
          ? 'Allowed'
          : 'Unknown',
    ],
    [
      'Size',
      status.SizeBytes
        ? `${(status.SizeBytes / 1024 ** 3).toFixed(2)} GB${status.Licensed ? ' (licensed)' : ''}`
        : 'Empty',
    ],
  ]
  return (
    <Box sx={{ mt: 2 }}>
      {!status.IsShared && (
        <Alert severity="error" sx={{ mb: 1 }}>
          This is a {status.RecipientTypeDetails}, not a shared mailbox.
        </Alert>
      )}
      <Box
        component="dl"
        aria-label="How it is set up now"
        sx={{
          m: 0,
          display: 'grid',
          gridTemplateColumns: { sm: '200px 1fr' },
          rowGap: 0.5,
          columnGap: 2,
          '& dt': { color: 'text.secondary' },
          '& dd': { m: 0 },
        }}
      >
        {rows.map(([label, value]) => (
          <Box key={label} sx={{ display: 'contents' }}>
            <Typography component="dt" variant="body2">
              {label}
            </Typography>
            <Typography component="dd" variant="body2">
              {value}
            </Typography>
          </Box>
        ))}
      </Box>
      {(status.Warnings ?? []).length > 0 && (
        <Alert severity="warning" sx={{ mt: 1 }}>
          {status.Warnings.join(' ')}
        </Alert>
      )}
    </Box>
  )
}

/**
 * Community Additions > Shared mailbox (add-on shared-mailbox): ask the customer the questions (PDF),
 * create or choose the mailbox, record their choices and apply them, then send them the "ready" PDF.
 */
export const CippSharedMailboxProcess = ({ tenant }) => {
  const validTenant = Boolean(tenant) && tenant !== 'AllTenants'
  const setup = ApiGetCall({
    url: '/api/ListSharedMailboxSetup',
    data: { tenantFilter: tenant },
    queryKey: `SharedMailboxSetup-${tenant}`,
    waiting: validTenant,
  })
  if (!validTenant)
    return (
      <Alert severity="info">
        Choose a single tenant at the top of the page.
      </Alert>
    )
  if (setup.isLoading) return <Skeleton variant="rounded" height={240} />
  if (setup.isError || !setup.data?.Options)
    return (
      <Alert severity="error">
        The shared mailbox options couldn&apos;t be loaded.
      </Alert>
    )
  return <SharedMailboxSteps key={tenant} tenant={tenant} setup={setup.data} />
}

/** The steps, once the questions have loaded: the form starts on our recommendations. */
const SharedMailboxSteps = ({ tenant, setup }) => {
  const options = setup.Options
  const formControl = useForm({
    mode: 'onChange',
    defaultValues: {
      mode: 'new',
      people: [],
      answers: defaultAnswers(options),
      blockSignIn: true,
      language: options.defaults?.language ?? 'en-GB',
      timeZone: options.defaults?.timeZone ?? 'GMT Standard Time',
    },
  })
  const values = useWatch({ control: formControl.control })
  const [includeGuide, setIncludeGuide] = useState(true)
  const [askedFor, setAskedFor] = useState('')
  const [doneAddress, setDoneAddress] = useState(null)
  const prefilledFor = useRef(null)

  const mailboxAddress =
    values.mode === 'existing' ? (values.mailbox?.value ?? '') : ''
  const statusAddress = mailboxAddress || doneAddress || ''
  const status = ApiGetCall({
    url: '/api/ListSharedMailboxSetup',
    data: { tenantFilter: tenant, Identity: statusAddress },
    queryKey: `SharedMailboxSetup-${tenant}-${statusAddress}`,
    waiting: Boolean(statusAddress),
    staleTime: 0,
  })
  const apply = ApiPostCall({
    relatedQueryKeys: [`SharedMailboxSetup-${tenant}*`],
  })

  // Choosing an existing mailbox fills in what it has now.
  useEffect(() => {
    const s = status.data?.Status
    if (
      values.mode !== 'existing' ||
      !s?.Exists ||
      prefilledFor.current === s.Address
    )
      return
    prefilledFor.current = s.Address
    setAnswers(formControl, answersFromStatus(options, s))
    formControl.setValue('people', peopleFromStatus(s))
    if (s.Group) formControl.setValue('groupName', s.Group.Name)
  }, [status.data, values.mode, options, formControl])

  // After a successful run, the result is the mailbox to report on.
  useEffect(() => {
    const address = apply.data?.data?.Address
    if (address) setDoneAddress(address)
  }, [apply.data])

  const questions = options?.questions ?? []
  const s = status.data?.Status
  const problem = sharedMailboxSetupProblem({
    ...values,
    hasSignatureRule: Boolean(s?.SignatureRule),
  })
  const body = sharedMailboxSetupBody(tenant, values)
  const reportAddress = doneAddress || mailboxAddress
  const mailboxes = (setup.Mailboxes ?? []).map((m) => ({
    value: m.Address,
    label: `${m.DisplayName} (${m.Address})`,
  }))

  return (
    <Stack spacing={2}>
      <Section
        number={1}
        title="Ask the customer"
        description="A PDF of the choices to send to the customer: what each option means for their team, what we recommend, and what to reply with."
      >
        <CippAddonPdfCard
          url="/api/ExecSharedMailboxCustomerPdf"
          body={{ tenantFilter: tenant, MailboxName: askedFor.trim() }}
          title="The choices, for the customer"
          description={`${questions.length} questions, each with its options, pros and cons, and our recommendation.`}
          fileName={addonPdfFileName('Shared_mailbox_choices', tenant)}
        >
          <TextField
            size="small"
            label="Mailbox they asked for (optional)"
            placeholder="info@contoso.co.uk"
            value={askedFor}
            onChange={(e) => setAskedFor(e.target.value)}
            slotProps={{ htmlInput: { maxLength: 254 } }}
            sx={{ maxWidth: 360 }}
          />
        </CippAddonPdfCard>
      </Section>

      <Section
        number={2}
        title="The mailbox"
        description="Create a new shared mailbox, or set up one the tenant already has. Running it again only changes what differs."
      >
        <ToggleButtonGroup
          exclusive
          size="small"
          value={values.mode}
          onChange={(_, mode) => mode && formControl.setValue('mode', mode)}
          aria-label="New or existing mailbox"
        >
          <ToggleButton value="new">New mailbox</ToggleButton>
          <ToggleButton value="existing">Existing mailbox</ToggleButton>
        </ToggleButtonGroup>
        {values.mode === 'new' ? (
          <Stack spacing={2} sx={{ mt: 2 }}>
            <CippFormComponent
              type="textField"
              name="displayName"
              label="Name (shown to people)"
              placeholder="Info"
              formControl={formControl}
            />
            <Stack
              direction={{ xs: 'column', sm: 'row' }}
              spacing={1}
              alignItems={{ sm: 'center' }}
            >
              <CippFormComponent
                type="textField"
                name="localPart"
                label="Address"
                placeholder="info"
                formControl={formControl}
              />
              <Typography sx={{ px: 0.5 }}>@</Typography>
              <Box sx={{ minWidth: 260, flexGrow: 1 }}>
                <CippFormDomainSelector
                  formControl={formControl}
                  name="domain"
                  label="Domain"
                />
              </Box>
            </Stack>
            <CippFormComponent
              type="textField"
              name="aliases"
              label="Other addresses it receives email for (optional)"
              placeholder="enquiries@contoso.co.uk, hello@contoso.co.uk"
              formControl={formControl}
            />
          </Stack>
        ) : (
          <Box sx={{ mt: 2 }}>
            <CippFormComponent
              type="autoComplete"
              name="mailbox"
              label="Shared mailbox"
              options={mailboxes}
              multiple={false}
              creatable={false}
              formControl={formControl}
            />
            {status.isFetching && (
              <Skeleton variant="rounded" height={120} sx={{ mt: 2 }} />
            )}
            {!status.isFetching && mailboxAddress && (
              <CurrentSetup status={s} />
            )}
          </Box>
        )}
      </Section>

      <Section
        number={3}
        title="The customer's choices"
        description="Who needs access, and the customer's answer to each question. Our recommendations are selected to start with."
      >
        <Stack spacing={3}>
          <CippFormUserSelector
            formControl={formControl}
            name="people"
            label="People who need access"
            multiple
            valueField="userPrincipalName"
          />
          <CippSharedMailboxChoices
            formControl={formControl}
            questions={questions}
            current={values.mode === 'existing' ? s?.Current : undefined}
          >
            {{
              grantVia: (v) =>
                v === 'group' ? (
                  <CippFormComponent
                    type="textField"
                    name="groupName"
                    label="Access group"
                    placeholder={`${options?.defaults?.accessGroupPrefix ?? 'SG-Mailbox-'}${values.localPart || 'info'}`}
                    helperText="Mail-enabled security group to create or reuse. Its members get access."
                    formControl={formControl}
                  />
                ) : null,
              signature: (v) =>
                v === 'rule' ? (
                  <CippFormComponent
                    type="textField"
                    name="signatureHtml"
                    label="Signature (HTML allowed)"
                    multiline
                    rows={4}
                    helperText={
                      s?.SignatureRule
                        ? 'Leave empty to keep the current signature.'
                        : 'Added to the bottom of every email sent from the shared address.'
                    }
                    formControl={formControl}
                  />
                ) : null,
              size: (v) =>
                v === 'licensed' ? (
                  <CippFormComponent
                    type="switch"
                    name="enableArchive"
                    label="Turn on the archive (once the mailbox has an Exchange Online licence)"
                    formControl={formControl}
                  />
                ) : null,
            }}
          </CippSharedMailboxChoices>
          <Accordion variant="outlined" disableGutters>
            <AccordionSummary expandIcon={<ExpandMore />}>
              <Typography variant="body2">More settings</Typography>
            </AccordionSummary>
            <AccordionDetails>
              <Stack spacing={1.5}>
                <CippFormComponent
                  type="switch"
                  name="blockSignIn"
                  label="Block sign-in to the mailbox itself (recommended)"
                  formControl={formControl}
                />
                <CippFormComponent
                  type="switch"
                  name="removeOthers"
                  label="Take access away from anyone not listed above"
                  formControl={formControl}
                />
                <CippFormComponent
                  type="switch"
                  name="reapplyAccess"
                  label="Re-grant Full Access to the people above, so Outlook matches the choice for how it appears (automapping can't be changed otherwise)"
                  formControl={formControl}
                />
                <Stack direction={{ xs: 'column', sm: 'row' }} spacing={2}>
                  <CippFormComponent
                    type="textField"
                    name="language"
                    label="Language"
                    formControl={formControl}
                  />
                  <CippFormComponent
                    type="textField"
                    name="timeZone"
                    label="Time zone"
                    formControl={formControl}
                  />
                </Stack>
              </Stack>
            </AccordionDetails>
          </Accordion>
          {values.answers?.grantVia === 'group' &&
            values.answers?.outlook === 'automap' && (
              <Alert severity="info">
                The mailbox won&apos;t appear in Outlook by itself through a
                group: each person adds it once. The guide for the customer
                explains how.
              </Alert>
            )}
          <Box>
            <Button
              variant="contained"
              disabled={Boolean(problem) || apply.isPending}
              onClick={() =>
                apply.mutate({ url: '/api/ExecSharedMailboxSetup', data: body })
              }
            >
              {values.mode === 'new'
                ? 'Create the shared mailbox'
                : `Apply to ${mailboxAddress || 'the mailbox'}`}
            </Button>
            {problem && (
              <Typography variant="body2" color="text.secondary" sx={{ mt: 1 }}>
                {problem}
              </Typography>
            )}
            <CippAddonStepResults action={apply} />
          </Box>
        </Stack>
      </Section>

      <Section
        number={4}
        title="Tell the customer it's ready"
        description="A PDF for the customer and their team: how the mailbox is set up, adding it to Outlook, sending from it and working together."
      >
        {reportAddress ? (
          <CippAddonPdfCard
            url="/api/ExecSharedMailboxSummaryPdf"
            body={{
              tenantFilter: tenant,
              Identity: reportAddress,
              Answers: values.answers,
              IncludeGuide: includeGuide,
            }}
            title={`Ready: ${reportAddress}`}
            description="Read from the tenant when it is made, so it shows the mailbox as it is now."
            fileName={addonPdfFileName('Shared_mailbox', reportAddress)}
          >
            <CippAddonGuideUpload
              addonId="shared-mailbox"
              guideKey="sending"
              title="Step-by-step guide"
              description="Your own guide with screenshots (a Word document), for example sending as the shared address in Outlook. It is kept in this CIPP instance and added to the end of every customer's PDF."
              guide={setup.Guide}
              include={includeGuide}
              onIncludeChange={setIncludeGuide}
              includeLabel="Add the guide to the end of the PDF"
              relatedQueryKeys={[`SharedMailboxSetup-${tenant}*`]}
            />
          </CippAddonPdfCard>
        ) : (
          <Typography variant="body2" color="text.secondary">
            Create or choose the mailbox first.
          </Typography>
        )}
      </Section>
    </Stack>
  )
}

export default CippSharedMailboxProcess
