import { useEffect, useRef } from 'react'
import {
  Alert,
  Box,
  Button,
  Checkbox,
  FormControlLabel,
  IconButton,
  MenuItem,
  Radio,
  RadioGroup,
  Stack,
  Switch,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  TextField,
  Tooltip,
  Typography,
} from '@mui/material'
import { Add, Delete, GroupAdd } from '@mui/icons-material'
import { Controller, useFieldArray, useForm, useWatch } from 'react-hook-form'
import { ApiPostCall } from '../../api/ApiCall'
import { CippFormUserSelector } from '../../components/CippComponents/CippFormUserSelector'
import { CippClaudeStepResults } from './CippClaudeStepResults'

const levelLabel = (l) => `Level ${l.number}: ${l.name}`

/** The changes (extras) a set of write scopes adds up to: every extra whose scopes are all there. */
export const changesFor = (extras, scopes) =>
  (extras ?? [])
    .filter(
      (e) =>
        (e.scopes ?? []).length > 0 &&
        e.scopes.every((s) => (scopes ?? []).includes(s))
    )
    .map((e) => e.id)

/** A table row filled from a level: it reads everything, and changes what the level allows. */
export const rowForLevel = (level, areas, extras) => ({
  read: Object.fromEntries((areas ?? []).map((a) => [a.id, true])),
  change: Object.fromEntries(
    changesFor(extras, level?.scopes).map((id) => [id, true])
  ),
})

/**
 * People who can use Claude now (the access group's members, or the people assigned directly),
 * as { value, label }.
 * @param {object} status
 */
const currentUsers = (status) => {
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
 * Form values for the access step from ListClaudeConnector's status. Everyone's level starts at
 * what the tenant has now, except when that is everything (what Microsoft's consent page approves)
 * or a mix that matches no level: then it starts at Read only, our recommendation. Each person
 * with their own access becomes a table row with what Claude can read and change for them.
 * @param {object} status
 */
export const claudeAccessDefaults = (status) => {
  const areas = status?.Options?.ReadAreas ?? []
  const levels = status?.Options?.Levels ?? []
  const extras = status?.Options?.Extras ?? []
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
    people: (access.People ?? []).map((p) => {
      const l = levels.find((x) => x.id === p.Level)
      const own = (p.Extras ?? []).flatMap(
        (id) => extras.find((e) => e.id === id)?.scopes ?? []
      )
      const reads = p.ReadAreas ?? on
      return {
        user: {
          value: p.UserId,
          label: p.Upn ? `${p.Name} (${p.Upn})` : p.Name,
        },
        read: Object.fromEntries(
          areas.map((a) => [a.id, reads.includes(a.id)])
        ),
        change: Object.fromEntries(
          changesFor(
            extras,
            p.Level === 'custom'
              ? [...(p.WriteScopes ?? []), ...(access.WriteScopes ?? [])]
              : [...(l?.scopes ?? []), ...own]
          ).map((id) => [id, true])
        ),
      }
    }),
  }
}

/**
 * ExecClaudeConnector Access body. Each row is sent as Level 1 plus its changes (extras) and the
 * read areas it has beyond everyone's. A change whose read area is off for that row is dropped
 * (the interlock: Claude can only change what it can read). People who had their own access
 * before and are no longer listed are sent with nothing, which removes it.
 */
export const claudeAccessBody = (tenant, values, status) => {
  const extras = status?.Options?.Extras ?? []
  const everyone = Object.entries(values.areas ?? {})
    .filter(([, on]) => on)
    .map(([id]) => id)
  const listed = (values.people ?? [])
    .filter((p) => p.user?.value ?? p.user)
    .map((p) => {
      const reads = Object.entries(p.read ?? {})
        .filter(([, on]) => on)
        .map(([id]) => id)
      const canRead = [...new Set([...everyone, ...reads])]
      return {
        User: p.user?.value ?? p.user,
        Level: 'read',
        Extras: extras
          .filter(
            (e) => p.change?.[e.id] && (!e.needs || canRead.includes(e.needs))
          )
          .map((e) => e.id),
        ReadAreas: reads.filter((id) => !everyone.includes(id)),
      }
    })
  const removed = (status?.Access?.People ?? [])
    .filter((p) => !listed.some((l) => l.User === p.UserId))
    .map((p) => ({ User: p.UserId, Level: 'read', Extras: [], ReadAreas: [] }))
  return {
    tenantFilter: tenant,
    Action: 'Access',
    ReadAreas: everyone,
    TenantLevel: values.tenantLevel,
    PeopleLevels: [...listed, ...removed],
  }
}

/** One person's row in the permissions table. */
const PersonRow = ({
  formControl,
  index,
  areas,
  extras,
  levels,
  everyone,
  onRemove,
}) => {
  const read =
    useWatch({ control: formControl.control, name: `people.${index}.read` }) ??
    {}
  const change =
    useWatch({
      control: formControl.control,
      name: `people.${index}.change`,
    }) ?? {}
  const canRead = (id) => everyone.includes(id) || Boolean(read[id])
  const readOnly = !extras.some(
    (e) => change[e.id] && (!e.needs || canRead(e.needs))
  )
  return (
    <TableRow>
      <TableCell sx={{ minWidth: 220 }}>
        <CippFormUserSelector
          formControl={formControl}
          name={`people.${index}.user`}
          label="Person"
          multiple={false}
        />
        <Typography
          variant="caption"
          color={readOnly ? 'text.secondary' : 'warning.main'}
        >
          {readOnly ? 'Read only' : 'Can change things'}
        </Typography>
      </TableCell>
      {areas.map((a) => {
        const fromEveryone = everyone.includes(a.id)
        return (
          <TableCell key={`r-${a.id}`} align="center" padding="checkbox">
            <Tooltip
              title={fromEveryone ? 'Everyone has this' : a.description}
              describeChild
            >
              <span>
                <Checkbox
                  size="small"
                  checked={fromEveryone || Boolean(read[a.id])}
                  disabled={fromEveryone}
                  onChange={(ev) => {
                    formControl.setValue(
                      `people.${index}.read.${a.id}`,
                      ev.target.checked
                    )
                    // Interlock: no change without its read area.
                    if (!ev.target.checked) {
                      extras
                        .filter((e) => e.needs === a.id)
                        .forEach((e) =>
                          formControl.setValue(
                            `people.${index}.change.${e.id}`,
                            false
                          )
                        )
                    }
                  }}
                  slotProps={{
                    input: {
                      'aria-label': `Read ${a.noun} for person ${index + 1}`,
                    },
                  }}
                />
              </span>
            </Tooltip>
          </TableCell>
        )
      })}
      {extras.map((e) => {
        const allowed = !e.needs || canRead(e.needs)
        return (
          <TableCell key={`c-${e.id}`} align="center" padding="checkbox">
            <Tooltip
              title={
                allowed
                  ? e.summary
                  : `Needs ${areas.find((a) => a.id === e.needs)?.noun ?? e.needs} to be readable first`
              }
              describeChild
            >
              <span>
                <Checkbox
                  size="small"
                  color="warning"
                  checked={allowed && Boolean(change[e.id])}
                  disabled={!allowed}
                  onChange={(ev) =>
                    formControl.setValue(
                      `people.${index}.change.${e.id}`,
                      ev.target.checked
                    )
                  }
                  slotProps={{
                    input: {
                      'aria-label': `${e.name} for person ${index + 1}`,
                    },
                  }}
                />
              </span>
            </Tooltip>
          </TableCell>
        )
      })}
      <TableCell sx={{ whiteSpace: 'nowrap' }}>
        <TextField
          select
          size="small"
          label="Fill as"
          value=""
          onChange={(ev) => {
            const l = levels.find((x) => x.id === ev.target.value)
            const row = rowForLevel(l, areas, extras)
            formControl.setValue(`people.${index}.read`, row.read)
            formControl.setValue(`people.${index}.change`, row.change)
          }}
          sx={{ minWidth: 110 }}
          slotProps={{
            htmlInput: { 'aria-label': `Fill person ${index + 1} as a level` },
          }}
        >
          {levels.map((l) => (
            <MenuItem key={l.id} value={l.id}>
              {levelLabel(l)}
            </MenuItem>
          ))}
        </TextField>
        <Tooltip title="Remove: they go back to everyone's access">
          <IconButton
            aria-label={`Remove person ${index + 1}`}
            onClick={onRemove}
          >
            <Delete />
          </IconButton>
        </Tooltip>
      </TableCell>
    </TableRow>
  )
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
  const extras = status?.Options?.Extras ?? []
  const current = status?.Access ?? {}
  const currentLevel = levels.find((l) => l.id === current.Level)
  const everyone = Object.entries(values.areas ?? {})
    .filter(([, on]) => on)
    .map(([id]) => id)

  // Fill the form from the tenant once per tenant (not on every refresh, so edits aren't lost).
  useEffect(() => {
    if (!status?.Options || loadedFor.current === tenant) return
    loadedFor.current = tenant
    formControl.reset(claudeAccessDefaults(status))
  }, [status, tenant]) // eslint-disable-line react-hooks/exhaustive-deps

  const noAreas = everyone.length === 0
  const everyoneLevel = levels.find((l) => l.id === values.tenantLevel)
  const newRow = (user) => ({
    user,
    read: Object.fromEntries(areas.map((a) => [a.id, everyone.includes(a.id)])),
    change: Object.fromEntries(
      changesFor(extras, everyoneLevel?.scopes).map((id) => [id, true])
    ),
  })
  const listedIds = (values.people ?? []).map((p) => p.user?.value ?? p.user)
  const notListed = currentUsers(status).filter(
    (u) => !listedIds.includes(u.value)
  )

  return (
    <Stack spacing={2.5} sx={{ maxWidth: 1100 }}>
      <Typography variant="body2" color="text.secondary">
        Claude only sees what each person can already see. Here you choose what
        it can read and change for everyone, and then person by person in the
        table.
      </Typography>

      {currentLevel && (
        <Typography variant="body2">
          Everyone currently has <strong>{levelLabel(currentLevel)}</strong>
          {(current.People ?? []).length > 0 &&
            `, and ${current.People.length} ${current.People.length === 1 ? 'person has' : 'people have'} their own access`}
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
        <Typography variant="subtitle1">Person by person</Typography>
        <Typography variant="body2" color="text.secondary" sx={{ mb: 1 }}>
          Tick what Claude can read and change for each person. Ticks that
          everyone has are greyed out; a person can't have less than everyone.
          Claude can only change something it can read for that person, so a
          change stays greyed out until its read is ticked. People not in the
          table get everyone's access. They also need to be one of the people
          who can use Claude (step 3).
        </Typography>
        <TableContainer sx={{ overflowX: 'auto' }}>
          <Table size="small" aria-label="Access person by person">
            <TableHead>
              <TableRow>
                <TableCell rowSpan={2}>Person</TableCell>
                <TableCell align="center" colSpan={areas.length}>
                  Claude can read
                </TableCell>
                <TableCell align="center" colSpan={extras.length}>
                  Claude can change
                </TableCell>
                <TableCell rowSpan={2} />
              </TableRow>
              <TableRow>
                {areas.map((a) => (
                  <TableCell key={`h-r-${a.id}`} align="center">
                    {a.label}
                  </TableCell>
                ))}
                {extras.map((e) => (
                  <TableCell key={`h-c-${e.id}`} align="center">
                    {e.name}
                  </TableCell>
                ))}
              </TableRow>
            </TableHead>
            <TableBody>
              {people.fields.map((f, index) => (
                <PersonRow
                  key={f.id}
                  formControl={formControl}
                  index={index}
                  areas={areas}
                  extras={extras}
                  levels={levels}
                  everyone={everyone}
                  onRemove={() => people.remove(index)}
                />
              ))}
              {people.fields.length === 0 && (
                <TableRow>
                  <TableCell colSpan={areas.length + extras.length + 2}>
                    <Typography variant="body2" color="text.secondary">
                      Nobody has their own access: everyone gets the settings
                      above.
                    </Typography>
                  </TableCell>
                </TableRow>
              )}
            </TableBody>
          </Table>
        </TableContainer>
        <Stack direction="row" spacing={1} sx={{ mt: 1 }}>
          <Button
            size="small"
            startIcon={<Add />}
            onClick={() => people.append(newRow(null))}
          >
            Add a person
          </Button>
          <Button
            size="small"
            startIcon={<GroupAdd />}
            disabled={notListed.length === 0}
            onClick={() => notListed.forEach((u) => people.append(newRow(u)))}
          >
            Add everyone who can use Claude
          </Button>
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
