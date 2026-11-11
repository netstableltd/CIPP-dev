import { useEffect, useRef } from 'react'
import {
  Alert,
  Box,
  Button,
  FormControlLabel,
  IconButton,
  MenuItem,
  Radio,
  RadioGroup,
  Stack,
  Switch,
  TextField,
  Tooltip,
  Typography,
} from '@mui/material'
import { Add, Delete } from '@mui/icons-material'
import { Controller, useFieldArray, useForm, useWatch } from 'react-hook-form'
import { ApiPostCall } from '../../api/ApiCall'
import { CippFormUserSelector } from '../../components/CippComponents/CippFormUserSelector'
import { CippAddonStepResults } from '../../components/CippAddons/CippAddonStepResults'

const levelLabel = (l) => `Level ${l.number}: ${l.name}`

/**
 * Form values for the access step from ListChatGPTConnector's status. Everyone's level starts at
 * what the tenant has now, except when that is everything (what approving in ChatGPT's admin console
 * gives) or a mix that matches no level: then it starts at Read only, our recommendation. People who
 * approved ChatGPT themselves are left out, so saving removes their approvals.
 * @param {object} status
 */
export const chatgptAccessDefaults = (status) => {
  const areas = status?.Options?.ReadAreas ?? []
  const access = status?.Access ?? {}
  const known = (access.TenantScopes ?? []).length > 0
  const on = known ? (access.ReadAreas ?? []) : areas.map((a) => a.id)
  const level =
    access.Level && !['custom', 'full'].includes(access.Level)
      ? access.Level
      : 'read'
  return {
    areas: Object.fromEntries(areas.map((a) => [a.id, on.includes(a.id)])),
    tenantLevel: level,
    people: (access.People ?? [])
      .filter((p) => !p.SelfApproved)
      .map((p) => ({
      user: { value: p.UserId, label: p.Upn ? `${p.Name} (${p.Upn})` : p.Name },
      level: p.Level === 'custom' ? 'full' : p.Level,
    })),
  }
}

/**
 * ExecChatGPTConnector Access body. People who had their own access before and are no longer
 * listed are sent as Read only, which removes it.
 */
export const chatgptAccessBody = (tenant, values, status) => {
  const listed = (values.people ?? [])
    .filter((p) => (p.user?.value ?? p.user) && p.level)
    .map((p) => ({ User: p.user?.value ?? p.user, Level: p.level }))
  const removed = (status?.Access?.People ?? [])
    .filter((p) => !listed.some((l) => l.User === p.UserId))
    .map((p) => ({ User: p.UserId, Level: 'read' }))
  return {
    tenantFilter: tenant,
    Action: 'Access',
    ReadAreas: Object.entries(values.areas ?? {})
      .filter(([, on]) => on)
      .map(([id]) => id),
    TenantLevel: values.tenantLevel,
    PeopleLevels: [...listed, ...removed],
  }
}

/** Step 3 of ChatGPT for Microsoft 365: what ChatGPT can read and change. Gives admin consent if there is none. */
export const CippChatGPTAccessStep = ({ tenant, status, disabled }) => {
  const formControl = useForm({
    defaultValues: { areas: {}, tenantLevel: 'read', people: [] },
  })
  const people = useFieldArray({ control: formControl.control, name: 'people' })
  const values = useWatch({ control: formControl.control })
  const save = ApiPostCall({
    relatedQueryKeys: [`ChatGPTConnector-${tenant}-*`],
  })
  const loadedFor = useRef(null)

  const levels = status?.Options?.Levels ?? []
  const areas = status?.Options?.ReadAreas ?? []
  const current = status?.Access ?? {}
  const currentLevel = levels.find((l) => l.id === current.Level)
  const consented = (current.TenantScopes ?? []).length > 0
  const selfApproved = (current.People ?? []).filter((p) => p.SelfApproved)

  // Fill the form from the tenant once per tenant (not on every refresh, so edits aren't lost).
  useEffect(() => {
    if (!status?.Options || loadedFor.current === tenant) return
    loadedFor.current = tenant
    formControl.reset(chatgptAccessDefaults(status))
  }, [status, tenant]) // eslint-disable-line react-hooks/exhaustive-deps

  const noAreas = !Object.values(values.areas ?? {}).some(Boolean)

  return (
    <Stack spacing={2.5} sx={{ maxWidth: 760 }}>
      <Typography variant="body2" color="text.secondary">
        ChatGPT only sees what each person can already see. Here you choose which
        of those things it can read, and what it can change: one level for
        everyone, and higher levels for named people.
      </Typography>

      {currentLevel && (
        <Typography variant="body2">
          Everyone currently has <strong>{levelLabel(currentLevel)}</strong>
          {(current.People ?? []).length > 0 &&
            `, and ${current.People.length} ${current.People.length === 1 ? 'person has' : 'people have'} their own level`}
          .
        </Typography>
      )}
      {current.Level === 'full' && (
        <Alert severity="warning">
          Everyone can currently send email, including from shared mailboxes,
          and change files or post in Teams. That is what approving ChatGPT in
          its own admin console gives. Choose a level below and save.
        </Alert>
      )}
      {!disabled && !consented && (
        <Alert severity="info">
          ChatGPT has no admin consent in this tenant yet. Saving gives it, for
          exactly what you choose here, so nobody gets more even for a moment.
          You don&apos;t need to approve anything in ChatGPT&apos;s admin
          console.
        </Alert>
      )}
      {selfApproved.length > 0 && (
        <Alert severity="warning">
          {selfApproved.map((p) => p.Upn ?? p.Name).join(', ')}{' '}
          {selfApproved.length === 1 ? 'has' : 'have'} approved ChatGPT for
          themselves. Saving removes those approvals, so they get the same
          access as everyone (or the level you give them below).
        </Alert>
      )}
      {current.Level === 'custom' && (
        <Alert severity="info">
          Everyone currently has a mix of permissions that matches no level (
          {(current.WriteScopes ?? []).join(', ') || 'none'}). Saving sets it to
          the level below.
        </Alert>
      )}

      <Box>
        <Typography variant="subtitle1">
          What ChatGPT can read, for everyone
        </Typography>
        {areas.map((a) => (
          <Box key={a.id}>
            <Controller
              name={`areas.${a.id}`}
              control={formControl.control}
              render={({ field }) => (
                <FormControlLabel
                  control={
                    <Switch
                      checked={Boolean(field.value)}
                      onChange={(e) => field.onChange(e.target.checked)}
                    />
                  }
                  label={
                    <span>
                      {a.label}{' '}
                      <Typography
                        component="span"
                        variant="body2"
                        color="text.secondary"
                      >
                        {a.description}
                      </Typography>
                    </span>
                  }
                />
              )}
            />
          </Box>
        ))}
        {noAreas && (
          <Typography variant="body2" color="error">
            Choose at least one thing ChatGPT can read.
          </Typography>
        )}
      </Box>

      <Box>
        <Typography variant="subtitle1">Access level for everyone</Typography>
        <Controller
          name="tenantLevel"
          control={formControl.control}
          render={({ field }) => (
            <RadioGroup
              value={field.value ?? ''}
              onChange={(e) => field.onChange(e.target.value)}
            >
              {levels.map((l) => (
                <FormControlLabel
                  key={l.id}
                  value={l.id}
                  control={<Radio />}
                  label={
                    <span>
                      <strong>{levelLabel(l)}</strong>{' '}
                      <Typography
                        component="span"
                        variant="body2"
                        color="text.secondary"
                      >
                        {l.tagline}. Risk: {l.risk.toLowerCase()}.
                        {l.id === 'read' ? ' Recommended to start with.' : ''}
                      </Typography>
                    </span>
                  }
                />
              ))}
            </RadioGroup>
          )}
        />
      </Box>

      <Box>
        <Typography variant="subtitle1">
          Higher levels for named people
        </Typography>
        <Typography variant="body2" color="text.secondary" sx={{ mb: 1 }}>
          Only what their level adds on top of everyone's. They also need to be
          one of the people who can use ChatGPT (step 2), and on ChatGPT Enterprise or Edu have a role with the extra actions on.
        </Typography>
        <Stack spacing={1.5}>
          {people.fields.map((f, index) => (
            <Stack
              key={f.id}
              direction={{ xs: 'column', sm: 'row' }}
              spacing={1}
              alignItems={{ sm: 'center' }}
            >
              <Box sx={{ flexGrow: 1, minWidth: 0 }}>
                <CippFormUserSelector
                  formControl={formControl}
                  name={`people.${index}.user`}
                  label="Person"
                  multiple={false}
                />
              </Box>
              <Controller
                name={`people.${index}.level`}
                control={formControl.control}
                render={({ field }) => (
                  <TextField
                    select
                    label="Level"
                    value={field.value ?? ''}
                    onChange={(e) => field.onChange(e.target.value)}
                    sx={{ minWidth: 240 }}
                    slotProps={{
                      htmlInput: {
                        'aria-label': `Level for person ${index + 1}`,
                      },
                    }}
                  >
                    {levels.map((l) => (
                      <MenuItem key={l.id} value={l.id}>
                        {levelLabel(l)}
                      </MenuItem>
                    ))}
                  </TextField>
                )}
              />
              <Tooltip title="Remove: they go back to everyone's level">
                <IconButton
                  aria-label={`Remove person ${index + 1}`}
                  onClick={() => people.remove(index)}
                >
                  <Delete />
                </IconButton>
              </Tooltip>
            </Stack>
          ))}
          <Box>
            <Button
              size="small"
              startIcon={<Add />}
              onClick={() => people.append({ user: null, level: 'drafts' })}
            >
              Add a person
            </Button>
          </Box>
        </Stack>
      </Box>

      <Box>
        <Button
          variant="contained"
          disabled={
            disabled || noAreas || !values.tenantLevel || save.isPending
          }
          onClick={() =>
            save.mutate({
              url: '/api/ExecChatGPTConnector',
              data: chatgptAccessBody(tenant, values, status),
            })
          }
        >
          {consented ? 'Save access' : 'Give consent for this access'}
        </Button>
        {disabled && (
          <Typography variant="body2" sx={{ mt: 1 }}>
            Add the ChatGPT app first.
          </Typography>
        )}
        <Typography
          variant="caption"
          color="text.secondary"
          component="p"
          sx={{ mt: 1 }}
        >
          If anyone approves ChatGPT's permissions again from its admin console
          (Review permissions in Microsoft Entra), it adds every permission for
          the actions turned on there. Come back and save this step afterwards.
        </Typography>
      </Box>
      <CippAddonStepResults action={save} />
    </Stack>
  )
}

export default CippChatGPTAccessStep
