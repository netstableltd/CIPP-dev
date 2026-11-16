import { useState } from 'react'
import {
  Alert,
  Box,
  Button,
  Card,
  CardContent,
  FormControlLabel,
  Link,
  Radio,
  RadioGroup,
  Skeleton,
  Stack,
  Switch,
  TextField,
  Typography,
} from '@mui/material'
import { ApiGetCall, ApiPostCall } from '../../api/ApiCall'
import {
  fillHandoverMessage,
  handoverSettingsBody,
  handoverSettingsProblem,
} from './passwordHandover'

const integrationUrl = '/cipp/integrations/configure?id=PWPush'

/** Where the links are made: CIPP's Password Pusher integration. */
const ServerStatus = ({ server }) => {
  if (!server?.Configured)
    return (
      <Alert severity="warning">
        No Password Pusher server is set up yet, so no password can be handed over.
        Add your server in{' '}
        <Link href={integrationUrl}>Settings &gt; Integrations &gt; Password Pusher</Link>{' '}
        (the address, and an API key if your server needs one). You don&apos;t need to switch
        the integration on for this add-on to use it.
      </Alert>
    )
  return (
    <Alert severity="success">
      Links are made on <b>{server.BaseUrl}</b>
      {server.Authenticated ? ', signed in with your API key' : ', without an API key'}.
      {server.IntegrationEnabled
        ? ' The integration is also switched on, so CIPP’s own password results (Reset Password, new users, TAP) give links too, with the integration’s own expiry settings.'
        : ''}{' '}
      <Link href={integrationUrl}>Change it</Link>.
    </Alert>
  )
}

/**
 * Community Additions > Password hand-over (add-on password-handover): the link and message settings
 * used by "Reset Password and Send Link" in the user actions menu.
 */
export const CippPasswordHandoverSettings = () => {
  const settings = ApiGetCall({
    url: '/api/ListPasswordHandover',
    queryKey: 'PasswordHandoverSettings',
  })
  if (settings.isLoading) return <Skeleton variant="rounded" height={240} />
  if (settings.isError || !settings.data?.Settings)
    return <Alert severity="error">The settings couldn&apos;t be loaded.</Alert>
  return (
    <SettingsForm
      key={settings.dataUpdatedAt ?? 'settings'}
      saved={settings.data.Settings}
      server={settings.data.Server}
    />
  )
}

const SettingsForm = ({ saved, server }) => {
  const [s, setS] = useState({
    expireAfterDays: saved.expireAfterDays,
    expireAfterViews: saved.expireAfterViews,
    passphrase: saved.passphrase,
    retrievalStep: saved.retrievalStep,
    mustChange: saved.mustChange,
    signInUrl: saved.signInUrl,
    subject: saved.subject,
    message: saved.message,
  })
  const save = ApiPostCall({ relatedQueryKeys: ['PasswordHandoverSettings'] })
  const set = (key) => (e) =>
    setS({ ...s, [key]: e.target.type === 'checkbox' ? e.target.checked : e.target.value })
  const problem = handoverSettingsProblem(s)
  const result = save.data?.data?.Results ?? save.error?.response?.data?.Results

  return (
    <Stack spacing={3}>
      <Typography variant="body1">
        Choose <b>Reset Password and Send Link</b> in a user&apos;s actions (Identity Management &gt;
        Users). It resets the password, puts the new one behind a link that stops working after a
        number of days or views, and gives you the message to send the customer.
      </Typography>
      <ServerStatus server={server} />

      <Card variant="outlined">
        <CardContent>
          <Typography variant="h6">The link</Typography>
          <Stack spacing={2} sx={{ mt: 2 }}>
            <Stack direction={{ xs: 'column', sm: 'row' }} spacing={2}>
              <TextField
                type="number"
                label="Lasts (days)"
                value={s.expireAfterDays}
                onChange={set('expireAfterDays')}
                slotProps={{ htmlInput: { min: 1, max: 90 } }}
              />
              <TextField
                type="number"
                label="Can be opened (times)"
                value={s.expireAfterViews}
                onChange={set('expireAfterViews')}
                slotProps={{ htmlInput: { min: 1, max: 100 } }}
              />
            </Stack>
            <Box>
              <Typography variant="subtitle2" id="handover-passphrase">
                Passphrase
              </Typography>
              <RadioGroup
                aria-labelledby="handover-passphrase"
                value={s.passphrase}
                onChange={set('passphrase')}
              >
                <FormControlLabel
                  value="email"
                  control={<Radio />}
                  label="The user's email address (anyone who finds the link also needs to know whose password it is)"
                />
                <FormControlLabel value="none" control={<Radio />} label="None" />
              </RadioGroup>
            </Box>
            <FormControlLabel
              control={<Switch checked={s.retrievalStep} onChange={set('retrievalStep')} />}
              label="Ask for a click before showing the password (stops email link scanners using up the views)"
            />
            <FormControlLabel
              control={<Switch checked={s.mustChange} onChange={set('mustChange')} />}
              label="Users choose their own password when they sign in (the default in the reset dialog)"
            />
          </Stack>
        </CardContent>
      </Card>

      <Card variant="outlined">
        <CardContent>
          <Typography variant="h6">The message to the customer</Typography>
          <Typography variant="body2" color="text.secondary" sx={{ mt: 0.5, mb: 2 }}>
            Placeholders:{' '}
            {(saved.placeholders ?? []).map((p) => `{${p.key}} ${p.what.toLowerCase()}`).join('; ')}.
          </Typography>
          <Stack spacing={2}>
            <TextField label="Sign-in address" value={s.signInUrl} onChange={set('signInUrl')} />
            <TextField label="Subject" value={s.subject} onChange={set('subject')} />
            <TextField
              label="Message"
              value={s.message}
              onChange={set('message')}
              multiline
              minRows={10}
            />
            <Box>
              <Typography variant="subtitle2">Preview</Typography>
              <Box
                aria-label="Message preview"
                sx={{
                  mt: 1,
                  p: 2,
                  borderRadius: 1,
                  bgcolor: 'action.hover',
                  whiteSpace: 'pre-wrap',
                  fontSize: 14,
                }}
              >
                <b>{fillHandoverMessage(s.subject, s)}</b>
                {'\n\n'}
                {fillHandoverMessage(s.message, s)}
              </Box>
            </Box>
          </Stack>
        </CardContent>
      </Card>

      {problem && <Alert severity="info">{problem}</Alert>}
      {result && (
        <Alert severity={save.isError ? 'error' : 'success'}>{String(result)}</Alert>
      )}
      <Stack direction="row" spacing={1.5}>
        <Button
          variant="contained"
          disabled={Boolean(problem) || save.isPending}
          onClick={() =>
            save.mutate({ url: '/api/ExecPasswordHandoverSettings', data: handoverSettingsBody(s) })
          }
        >
          Save settings
        </Button>
        <Button
          variant="outlined"
          disabled={save.isPending || !saved.Saved}
          onClick={() =>
            save.mutate({ url: '/api/ExecPasswordHandoverSettings', data: { Reset: true } })
          }
        >
          Back to the defaults
        </Button>
      </Stack>
    </Stack>
  )
}

export default CippPasswordHandoverSettings
