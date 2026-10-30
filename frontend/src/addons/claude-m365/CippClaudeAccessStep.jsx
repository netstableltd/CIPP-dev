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
import { CippClaudeStepResults } from './CippClaudeStepResults'

const levelLabel = (l) => `Level ${l.number}: ${l.name}`

/**
 * Form values for the access step from ListClaudeConnector's status. Everyone's level starts at
 * what the tenant has now, except when that is everything (what Microsoft's consent page approves)
 * or a mix that matches no level: then it starts at Read only, our recommendation.
 * @param {object} status
 */
export const claudeAccessDefaults = (status) => {
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
    people: (access.People ?? []).map((p) => ({
      user: { value: p.UserId, label: p.Upn ? `${p.Name} (${p.Upn})` : p.Name },
      level: p.Level === 'custom' ? 'full' : p.Level,
    })),
  }
}

/**
 * ExecClaudeConnector Access body. People who had their own access before and are no longer
 * listed are sent as Read only, which removes it.
 */
export const claudeAccessBody = (tenant, values, status) => {
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

/** Step 4 of Claude for Microsoft 365: what Claude can read and change. */
export const CippClaudeAccessStep = ({ tenant, status, disabled }) => {
  const formControl = useForm({
    defaultValues: { areas: {}, tenantLevel: 'read', people: [] },
  })
  const people = useFieldArray({ control: formControl.control, name: 'people' })
  const values = useWatch({ control: formControl.control })
  const save = ApiPostCall({
    relatedQueryKeys: [`ClaudeConnector-${tenant}-*`],
  })
  const loadedFor = useRef(null)

  const levels = status?.Options?.Levels ?? []
  const areas = status?.Options?.ReadAreas ?? []
  const current = status?.Access ?? {}
  const currentLevel = levels.find((l) => l.id === current.Level)

  // Fill the form from the tenant once per tenant (not on every refresh, so edits aren't lost).
  useEffect(() => {
    if (!status?.Options || loadedFor.current === tenant) return
    loadedFor.current = tenant
    formControl.reset(claudeAccessDefaults(status))
  }, [status, tenant]) // eslint-disable-line react-hooks/exhaustive-deps

  const noAreas = !Object.values(values.areas ?? {}).some(Boolean)

  return (
    <Stack spacing={2.5} sx={{ maxWidth: 760 }}>
      <Typography variant="body2" color="text.secondary">
        Claude only sees what each person can already see. Here you choose which
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
          Microsoft's consent page approves every permission Anthropic's app
          asks for, so everyone can currently send email, change files and post
          in Teams. Choose a level below and save.
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
          What Claude can read, for everyone
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
            Choose at least one thing Claude can read.
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
          one of the people who can use Claude (step 3).
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
              url: '/api/ExecClaudeConnector',
              data: claudeAccessBody(tenant, values, status),
            })
          }
        >
          Save access
        </Button>
        {disabled && (
          <Typography variant="body2" sx={{ mt: 1 }}>
            Both apps need admin consent first.
          </Typography>
        )}
        <Typography
          variant="caption"
          color="text.secondary"
          component="p"
          sx={{ mt: 1 }}
        >
          If anyone approves Microsoft's consent page again, it gives everyone
          every permission again. Come back and save this step afterwards.
        </Typography>
      </Box>
      <CippClaudeStepResults action={save} />
    </Stack>
  )
}

export default CippClaudeAccessStep
