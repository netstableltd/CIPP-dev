import { useEffect, useMemo, useState } from 'react'
import {
  Alert,
  Box,
  Button,
  Card,
  CardContent,
  CardHeader,
  Checkbox,
  Chip,
  Divider,
  FormControlLabel,
  IconButton,
  Stack,
  Switch,
  TextField,
  Typography,
} from '@mui/material'
import { Grid } from '@mui/system'
import { ApiGetCall, ApiPostCall } from '../../api/ApiCall'
import { CippApiResults } from '../CippComponents/CippApiResults'
import { ServerPdfPane, useServerPdf } from '../CippPdf/useServerPdf'
import { CippIcons } from '../../utils/icon-registry'

const statusColour = { Draft: 'warning', Approved: 'info', Sent: 'success' }

// Saved overrides -> editor state (and back), so a reload shows exactly what was saved.
export const overridesToState = (o = {}) => ({
  note: o.Note ?? '',
  hiddenSections: new Set(o.HiddenSections ?? []),
  hiddenFindings: new Set(o.HiddenFindings ?? []),
  text: { ...(o.FindingText ?? {}) },
  items: Object.fromEntries(
    Object.entries(o.FindingItems ?? {}).map(([k, v]) => [
      k,
      Array.isArray(v) ? v.join(', ') : String(v ?? ''),
    ])
  ),
  extra: (o.Extra ?? []).map((e) => ({
    text: e.text ?? '',
    plan: Boolean(e.plan),
  })),
})

export const stateToOverrides = (s, findings = []) => {
  const byId = Object.fromEntries(findings.map((f) => [f.Id, f]))
  const text = {}
  for (const [id, v] of Object.entries(s.text)) {
    const t = (v ?? '').trim()
    if (t && t !== (byId[id]?.Customer ?? '').trim()) text[id] = t
  }
  const items = {}
  for (const [id, v] of Object.entries(s.items)) {
    const original = (byId[id]?.CustomerItems ?? []).join(', ')
    if ((v ?? '').trim() !== original) items[id] = v
  }
  return {
    Note: s.note.trim(),
    HiddenSections: [...s.hiddenSections],
    HiddenFindings: [...s.hiddenFindings],
    FindingText: text,
    FindingItems: items,
    Extra: s.extra.filter((e) => e.text.trim()),
  }
}

/**
 * Review page for one customer report draft: change the note, sections and recommendations,
 * regenerate the PDF, then approve and send. Edits only change what the customer sees.
 */
export const CippReportDraftEditor = ({ id, onClosed }) => {
  const draftApi = ApiGetCall({
    url: `/api/ListReportDrafts?Id=${encodeURIComponent(id ?? '')}`,
    queryKey: `ListReportDrafts-${id}`,
    waiting: !!id,
  })
  const catalog = ApiGetCall({
    url: '/api/ListReportSections',
    queryKey: 'ListReportSections',
  })
  const action = ApiPostCall({
    relatedQueryKeys: [`ListReportDrafts-${id}`, 'ListReportDrafts'],
  })
  const draft =
    draftApi.data && !Array.isArray(draftApi.data) ? draftApi.data : null

  const [state, setState] = useState(overridesToState())
  const [dirty, setDirty] = useState(false)
  useEffect(() => {
    if (draft) {
      setState(overridesToState(draft.Overrides ?? {}))
      setDirty(false)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [draftApi.dataUpdatedAt])

  const update = (fn) => {
    setState((prev) => fn({ ...prev }))
    setDirty(true)
  }
  const toggle = (setName, key) =>
    update((s) => {
      const next = new Set(s[setName])
      next.has(key) ? next.delete(key) : next.add(key)
      return { ...s, [setName]: next }
    })

  const findings = useMemo(() => draft?.Findings ?? [], [draft])
  const customer = findings.filter((f) => f.Customer)
  const internal = findings.filter((f) => !f.Customer)
  const now = customer.filter((f) => f.Severity !== 'Info')
  const plan = customer.filter((f) => f.Severity === 'Info')
  const labels = Object.fromEntries(
    (Array.isArray(catalog.data) ? catalog.data : []).map((c) => [
      c.value,
      c.label,
    ])
  )
  const editable = draft?.Status === 'Draft'

  const pdf = useServerPdf({
    url: `/api/ExecGetReportBuilderPdf?id=${encodeURIComponent(draft?.ReportGUID ?? '')}`,
    enabled: !!draft?.ReportGUID,
  })

  const post = (data) => action.mutate({ url: '/api/ExecReportDraft', data })
  const regenerate = () =>
    post({
      Action: 'Generate',
      TenantId: draft.TenantId,
      Period: draft.PeriodKey,
      Overrides: stateToOverrides(state, findings),
    })

  if (!id) return <Alert severity="error">No draft selected.</Alert>
  if (draftApi.isError)
    return <Alert severity="error">The draft could not be loaded.</Alert>
  if (!draft)
    return <Typography color="text.secondary">Loading draft…</Typography>

  const finding = (f) => {
    const hidden = state.hiddenFindings.has(f.Id)
    return (
      <Box key={f.Id} sx={{ py: 1.5 }}>
        <FormControlLabel
          control={
            <Checkbox
              checked={!hidden}
              disabled={!editable}
              onChange={() => toggle('hiddenFindings', f.Id)}
              slotProps={{ input: { 'aria-label': `Include ${f.Title}` } }}
            />
          }
          label={<Typography variant="subtitle2">{f.Title}</Typography>}
        />
        {!hidden && (
          <Stack spacing={1} sx={{ pl: 4 }}>
            <TextField
              label="Recommendation"
              multiline
              minRows={2}
              size="small"
              disabled={!editable}
              value={state.text[f.Id] ?? f.Customer}
              onChange={(e) => {
                const v = e.target.value
                update((s) => ({ ...s, text: { ...s.text, [f.Id]: v } }))
              }}
            />
            <TextField
              label="Affected (comma separated)"
              size="small"
              disabled={!editable}
              value={state.items[f.Id] ?? (f.CustomerItems ?? []).join(', ')}
              onChange={(e) => {
                const v = e.target.value
                update((s) => ({ ...s, items: { ...s.items, [f.Id]: v } }))
              }}
            />
            <Typography variant="caption" color="text.secondary">
              For us: {f.Detail}
            </Typography>
          </Stack>
        )}
      </Box>
    )
  }

  return (
    <Grid container spacing={2}>
      <Grid size={{ xs: 12, lg: 5 }}>
        <Stack spacing={2}>
          <Card>
            <CardHeader
              title={`${draft.Company} – ${draft.PeriodLabel}`}
              subheader={`Generated ${new Date(draft.GeneratedAt).toLocaleString()} by ${draft.GeneratedBy}`}
              action={
                <Chip
                  label={draft.Status}
                  color={statusColour[draft.Status] ?? 'default'}
                />
              }
            />
            <CardContent>
              <Stack spacing={1}>
                {draft.Status === 'Approved' && (
                  <Alert severity="info">
                    Approved by {draft.ApprovedBy}. Reopen it to make more
                    changes.
                  </Alert>
                )}
                {draft.Status === 'Sent' && (
                  <Alert severity="success">
                    Sent to {draft.SentTo} on{' '}
                    {new Date(draft.SentAt).toLocaleString()}.
                  </Alert>
                )}
                {editable && dirty && (
                  <Alert severity="warning">
                    You have unsaved changes. Save to update the PDF before
                    approving.
                  </Alert>
                )}
                <Stack
                  direction="row"
                  spacing={1}
                  sx={{ flexWrap: 'wrap', gap: 1 }}
                >
                  {editable && (
                    <Button
                      variant="contained"
                      disabled={!dirty || action.isPending}
                      onClick={regenerate}
                    >
                      Save and update PDF
                    </Button>
                  )}
                  {editable && (
                    <Button
                      variant="outlined"
                      color="success"
                      disabled={dirty || action.isPending}
                      onClick={() => post({ Action: 'Approve', Id: draft.Id })}
                    >
                      Approve
                    </Button>
                  )}
                  {draft.Status === 'Approved' && (
                    <>
                      <Button
                        variant="contained"
                        disabled={action.isPending}
                        onClick={() => post({ Action: 'Send', Id: draft.Id })}
                      >
                        Send to customer
                      </Button>
                      <Button
                        variant="outlined"
                        onClick={() => post({ Action: 'Reopen', Id: draft.Id })}
                      >
                        Reopen
                      </Button>
                    </>
                  )}
                  {draft.Status !== 'Sent' && (
                    <Button
                      variant="text"
                      onClick={() =>
                        post({
                          Action: 'Generate',
                          TenantId: draft.TenantId,
                          Period: draft.PeriodKey,
                        })
                      }
                      disabled={action.isPending || draft.Status !== 'Draft'}
                    >
                      Refresh data
                    </Button>
                  )}
                  {draft.Status !== 'Sent' && (
                    <Button
                      variant="text"
                      color="error"
                      onClick={() => {
                        post({ Action: 'Discard', Id: draft.Id })
                        onClosed?.()
                      }}
                    >
                      Discard
                    </Button>
                  )}
                </Stack>
                <CippApiResults apiObject={action} />
              </Stack>
            </CardContent>
          </Card>

          <Card>
            <CardHeader
              title="Note from your IT team"
              subheader="Shown in a box on the summary page. Leave empty for none."
            />
            <CardContent>
              <TextField
                fullWidth
                multiline
                minRows={3}
                disabled={!editable}
                value={state.note}
                onChange={(e) => {
                  const v = e.target.value
                  update((s) => ({ ...s, note: v }))
                }}
                slotProps={{
                  htmlInput: {
                    'aria-label': 'Note from your IT team',
                    maxLength: 2000,
                  },
                }}
              />
            </CardContent>
          </Card>

          <Card>
            <CardHeader
              title="Sections"
              subheader="Untick a section to leave it out of this month's report only."
            />
            <CardContent>
              {(draft.Sections ?? []).map((sid) => (
                <FormControlLabel
                  key={sid}
                  sx={{ display: 'flex' }}
                  control={
                    <Checkbox
                      checked={!state.hiddenSections.has(sid)}
                      disabled={!editable}
                      onChange={() => toggle('hiddenSections', sid)}
                    />
                  }
                  label={labels[sid] ?? sid}
                />
              ))}
            </CardContent>
          </Card>

          <Card>
            <CardHeader
              title="Recommendations"
              subheader="Untick to leave one out, or change the wording the customer sees."
            />
            <CardContent>
              <Typography variant="overline">To do now</Typography>
              {now.length === 0 && (
                <Typography color="text.secondary">None.</Typography>
              )}
              {now.map(finding)}
              <Divider sx={{ my: 1 }} />
              <Typography variant="overline">To plan for</Typography>
              {plan.length === 0 && (
                <Typography color="text.secondary">None.</Typography>
              )}
              {plan.map(finding)}
              <Divider sx={{ my: 1 }} />
              <Typography variant="overline">Added by you</Typography>
              {state.extra.map((e, i) => (
                <Stack
                  key={i}
                  direction="row"
                  spacing={1}
                  sx={{ alignItems: 'center', py: 1 }}
                >
                  <TextField
                    fullWidth
                    multiline
                    size="small"
                    label="Recommendation"
                    disabled={!editable}
                    value={e.text}
                    onChange={(ev) => {
                      const v = ev.target.value
                      update((s) => ({
                        ...s,
                        extra: s.extra.map((x, j) =>
                          j === i ? { ...x, text: v } : x
                        ),
                      }))
                    }}
                  />
                  <FormControlLabel
                    control={
                      <Switch
                        checked={e.plan}
                        disabled={!editable}
                        onChange={(ev) => {
                          const v = ev.target.checked
                          update((s) => ({
                            ...s,
                            extra: s.extra.map((x, j) =>
                              j === i ? { ...x, plan: v } : x
                            ),
                          }))
                        }}
                      />
                    }
                    label="Plan for"
                  />
                  <IconButton
                    aria-label="Remove recommendation"
                    disabled={!editable}
                    onClick={() =>
                      update((s) => ({
                        ...s,
                        extra: s.extra.filter((_, j) => j !== i),
                      }))
                    }
                  >
                    <CippIcons.Delete />
                  </IconButton>
                </Stack>
              ))}
              <Button
                size="small"
                disabled={!editable || state.extra.length >= 10}
                onClick={() =>
                  update((s) => ({
                    ...s,
                    extra: [...s.extra, { text: '', plan: false }],
                  }))
                }
              >
                Add a recommendation
              </Button>
            </CardContent>
          </Card>

          {internal.length > 0 && (
            <Card>
              <CardHeader title="Pre-check items (not shown to the customer)" />
              <CardContent>
                {internal.map((f) => (
                  <Box key={f.Id} sx={{ py: 0.5 }}>
                    <Typography variant="subtitle2">
                      {f.Severity}: {f.Title}
                    </Typography>
                    <Typography variant="caption" color="text.secondary">
                      {f.Detail}
                    </Typography>
                  </Box>
                ))}
              </CardContent>
            </Card>
          )}
        </Stack>
      </Grid>
      <Grid size={{ xs: 12, lg: 7 }}>
        <Box
          sx={{
            height: 'calc(100vh - 160px)',
            minHeight: 600,
            position: 'sticky',
            top: 16,
          }}
        >
          <ServerPdfPane
            {...pdf}
            title="Report preview"
            errorText="The draft PDF could not be loaded."
          />
        </Box>
      </Grid>
    </Grid>
  )
}

export default CippReportDraftEditor
