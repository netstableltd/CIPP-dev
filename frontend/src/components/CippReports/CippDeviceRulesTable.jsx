import { Fragment, useEffect, useMemo, useState } from 'react'
import {
  Alert,
  Box,
  Button,
  Chip,
  MenuItem,
  Stack,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  TextField,
  Typography,
} from '@mui/material'
import { ApiGetCall, ApiPostCall } from '../../api/ApiCall'
import { CippApiResults } from '../CippComponents/CippApiResults'

const severities = [
  { value: 'attention', label: 'Needs attention' },
  { value: 'check', label: 'Check' },
  { value: 'off', label: 'Off' },
]

// What each kind of rule means, shown under the numbers.
const kindHelp = {
  below: { check: 'at or below', attention: 'below' },
  above: { check: 'above', attention: 'above' },
}

const blankToNull = (v) =>
  v === '' || v === null || v === undefined ? null : Number(v)
const shown = (v) => (v === null || v === undefined ? '' : String(v))

/**
 * Editable table of the device rules that rate computers in Reports as Good / Check / Needs attention.
 * Loads from ListReportDeviceRules and saves to ExecReportDeviceRules.
 */
export const CippDeviceRulesTable = () => {
  const rules = ApiGetCall({
    url: '/api/ListReportDeviceRules',
    queryKey: 'ListReportDeviceRules',
  })
  const save = ApiPostCall({ relatedQueryKeys: ['ListReportDeviceRules'] })
  const [edits, setEdits] = useState({})

  const list = useMemo(() => rules.data?.Rules ?? [], [rules.data])
  useEffect(() => {
    setEdits({})
  }, [rules.dataUpdatedAt])

  const value = (rule, field) =>
    edits[rule.id]?.[field] !== undefined
      ? edits[rule.id][field]
      : shown(rule[field])
  const setValue = (rule, field, v) =>
    setEdits((prev) => ({
      ...prev,
      [rule.id]: { ...(prev[rule.id] ?? {}), [field]: v },
    }))
  const dirty = Object.keys(edits).length > 0

  const payload = () =>
    list.map((rule) => {
      if (rule.kind === 'flag')
        return { id: rule.id, severity: value(rule, 'severity') }
      if (rule.kind === 'setting')
        return { id: rule.id, value: blankToNull(value(rule, 'value')) }
      return {
        id: rule.id,
        check: blankToNull(value(rule, 'check')),
        attention: blankToNull(value(rule, 'attention')),
      }
    })

  const groups = useMemo(() => {
    const out = []
    for (const rule of list) {
      const g = out.find((x) => x.name === rule.group)
      if (g) g.rules.push(rule)
      else out.push({ name: rule.group, rules: [rule] })
    }
    return out
  }, [list])

  const numberField = (rule, field, label) => (
    <TextField
      size="small"
      type="number"
      value={value(rule, field)}
      onChange={(e) => setValue(rule, field, e.target.value)}
      placeholder="never"
      slotProps={{
        htmlInput: { min: 0, 'aria-label': `${rule.label} ${label}` },
      }}
      sx={{ width: 150 }}
      helperText={
        rule.kind === 'setting'
          ? rule.unit
          : `${kindHelp[rule.kind]?.[field] ?? ''} this${rule.unit ? ` (${rule.unit})` : ''}`
      }
    />
  )

  return (
    <Stack spacing={2}>
      <Alert severity="info">
        These rules rate every computer in the monthly reports as Good, Check or
        Needs attention. A computer gets the worst rating of any rule it meets.
        Leave a box blank to never use that level. Changes apply to the next
        report generated; the device list in the Report Builder updates at the
        next Atera sync.
      </Alert>
      {rules.isError && (
        <Alert severity="error">Could not load the device rules.</Alert>
      )}
      <TableContainer>
        <Table size="small">
          <TableHead>
            <TableRow>
              <TableCell>Rule</TableCell>
              <TableCell>Check when</TableCell>
              <TableCell>Needs attention when</TableCell>
              <TableCell>Default</TableCell>
            </TableRow>
          </TableHead>
          <TableBody>
            {groups.map((group) => (
              <Fragment key={group.name}>
                <TableRow>
                  <TableCell colSpan={4} sx={{ bgcolor: 'action.hover' }}>
                    <Typography variant="subtitle2">{group.name}</Typography>
                  </TableCell>
                </TableRow>
                {group.rules.map((rule) => (
                  <TableRow key={rule.id}>
                    <TableCell sx={{ maxWidth: 360 }}>
                      <Typography variant="body2">
                        {rule.label}{' '}
                        {!rule.isDefault && (
                          <Chip size="small" label="changed" sx={{ ml: 0.5 }} />
                        )}
                      </Typography>
                      {rule.help && (
                        <Typography variant="caption" color="text.secondary">
                          {rule.help}
                        </Typography>
                      )}
                    </TableCell>
                    {rule.kind === 'flag' && (
                      <TableCell colSpan={2}>
                        <TextField
                          select
                          size="small"
                          value={value(rule, 'severity')}
                          onChange={(e) =>
                            setValue(rule, 'severity', e.target.value)
                          }
                          sx={{ width: 200 }}
                          slotProps={{
                            htmlInput: { 'aria-label': `${rule.label} rating` },
                          }}
                        >
                          {severities.map((s) => (
                            <MenuItem key={s.value} value={s.value}>
                              {s.label}
                            </MenuItem>
                          ))}
                        </TextField>
                      </TableCell>
                    )}
                    {rule.kind === 'setting' && (
                      <TableCell colSpan={2}>
                        {numberField(rule, 'value', 'value')}
                      </TableCell>
                    )}
                    {(rule.kind === 'below' || rule.kind === 'above') && (
                      <>
                        <TableCell>
                          {numberField(rule, 'check', 'check')}
                        </TableCell>
                        <TableCell>
                          {numberField(rule, 'attention', 'needs attention')}
                        </TableCell>
                      </>
                    )}
                    <TableCell>
                      <Typography variant="caption" color="text.secondary">
                        {rule.kind === 'flag'
                          ? severities.find(
                              (s) => s.value === rule.default?.severity
                            )?.label
                          : rule.kind === 'setting'
                            ? shown(rule.default?.value)
                            : `${shown(rule.default?.check) || 'never'} / ${shown(rule.default?.attention) || 'never'}`}
                      </Typography>
                    </TableCell>
                  </TableRow>
                ))}
              </Fragment>
            ))}
          </TableBody>
        </Table>
      </TableContainer>
      <Box>
        <Stack direction="row" spacing={1}>
          <Button
            variant="contained"
            disabled={!dirty || save.isPending || rules.isFetching}
            onClick={() =>
              save.mutate({
                url: '/api/ExecReportDeviceRules',
                data: { Rules: payload() },
              })
            }
          >
            Save rules
          </Button>
          <Button
            variant="outlined"
            disabled={!dirty}
            onClick={() => setEdits({})}
          >
            Undo changes
          </Button>
          <Button
            variant="text"
            color="warning"
            disabled={save.isPending || list.every((r) => r.isDefault)}
            onClick={() =>
              save.mutate({
                url: '/api/ExecReportDeviceRules',
                data: { Action: 'Reset' },
              })
            }
          >
            Reset to defaults
          </Button>
        </Stack>
        <CippApiResults apiObject={save} />
        {rules.data?.LastModifiedBy && (
          <Typography variant="caption" color="text.secondary">
            Last saved by {rules.data.LastModifiedBy}
            {rules.data.LastModified
              ? ` on ${new Date(rules.data.LastModified).toLocaleString()}`
              : ''}
          </Typography>
        )}
      </Box>
    </Stack>
  )
}

export default CippDeviceRulesTable
