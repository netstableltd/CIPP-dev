import { useState } from 'react'
import { Controller } from 'react-hook-form'
import {
  Autocomplete,
  Box,
  Chip,
  IconButton,
  Paper,
  Stack,
  SvgIcon,
  TextField,
  Tooltip,
  Typography,
} from '@mui/material'
import { CippIcons } from '../../utils/icon-registry'
import { ApiGetCall } from '../../api/ApiCall'
import {
  addSection,
  describeSections,
  moveSection,
  removeSection,
} from '../../utils/report-sections'

/**
 * Ordered list of report sections with drag-to-reorder.
 *
 * Holds an array of { label, value } in the form field `name` (the same shape an autocomplete
 * would hold, so CippApiDialog's setDefaultValues pre-fills it when the field is declared with
 * type 'autoComplete'). Sections are added from /api/ListReportSections and reordered by
 * dragging the handle, or with the up/down buttons (keyboard and touch screens, where native
 * drag-and-drop is not available).
 */
export const CippReportSectionsPicker = ({
  formControl,
  name,
  label = 'Report sections',
  helperText,
  emptyText = 'No sections chosen.',
  disabled = false,
}) => {
  const catalog = ApiGetCall({
    url: '/api/ListReportSections',
    queryKey: 'ListReportSections',
  })
  const options = Array.isArray(catalog.data) ? catalog.data : []
  const [dragIndex, setDragIndex] = useState(null)
  const [overIndex, setOverIndex] = useState(null)
  const [inputValue, setInputValue] = useState('')

  const endDrag = () => {
    setDragIndex(null)
    setOverIndex(null)
  }

  return (
    <Controller
      name={name}
      control={formControl.control}
      defaultValue={[]}
      render={({ field }) => {
        const rows = describeSections(field.value, options)
        const commit = (next) =>
          field.onChange(next.map((s) => ({ label: s.label, value: s.value })))
        const chosen = new Set(rows.map((r) => r.value))
        const available = options.filter((o) => !chosen.has(o.value))

        return (
          <Stack spacing={1}>
            <Typography variant="subtitle2">{label}</Typography>
            {helperText && (
              <Typography variant="body2" color="text.secondary">
                {helperText}
              </Typography>
            )}

            {rows.length === 0 ? (
              <Paper
                variant="outlined"
                sx={{ p: 2, color: 'text.secondary', fontSize: 14 }}
              >
                {emptyText}
              </Paper>
            ) : (
              <Paper variant="outlined" component="ol" sx={{ m: 0, p: 0 }}>
                {rows.map((row, index) => (
                  <Box
                    component="li"
                    key={row.value}
                    draggable={!disabled}
                    onDragStart={(e) => {
                      setDragIndex(index)
                      e.dataTransfer.effectAllowed = 'move'
                      // Firefox only starts a drag when some data is set.
                      e.dataTransfer.setData('text/plain', String(index))
                    }}
                    onDragOver={(e) => {
                      if (dragIndex === null) return
                      e.preventDefault()
                      e.dataTransfer.dropEffect = 'move'
                      if (overIndex !== index) setOverIndex(index)
                    }}
                    onDrop={(e) => {
                      e.preventDefault()
                      if (dragIndex !== null)
                        commit(moveSection(rows, dragIndex, index))
                      endDrag()
                    }}
                    onDragEnd={endDrag}
                    sx={{
                      listStyle: 'none',
                      display: 'flex',
                      alignItems: 'center',
                      gap: 1,
                      px: 1,
                      py: 0.75,
                      borderTop: index === 0 ? 'none' : '1px solid',
                      borderColor: 'divider',
                      bgcolor:
                        overIndex === index && dragIndex !== index
                          ? 'action.hover'
                          : 'transparent',
                      opacity: dragIndex === index ? 0.5 : 1,
                      boxShadow:
                        overIndex === index &&
                        dragIndex !== null &&
                        dragIndex !== index
                          ? (theme) =>
                              `inset 0 ${dragIndex > index ? 2 : -2}px 0 ${theme.palette.primary.main}`
                          : 'none',
                    }}
                  >
                    <SvgIcon
                      fontSize="small"
                      sx={{
                        color: 'text.secondary',
                        cursor: disabled ? 'default' : 'grab',
                      }}
                      aria-hidden="true"
                    >
                      <CippIcons.DragIndicator />
                    </SvgIcon>
                    <Typography
                      variant="body2"
                      color="text.secondary"
                      sx={{ width: 20, textAlign: 'right' }}
                    >
                      {index + 1}.
                    </Typography>
                    <Box sx={{ flex: 1, minWidth: 0 }}>
                      <Typography
                        variant="body2"
                        sx={{ fontWeight: 500 }}
                        color={row.missing ? 'error' : 'text.primary'}
                        noWrap
                      >
                        {row.missing ? `${row.label} (missing)` : row.label}
                      </Typography>
                      {row.description && (
                        <Typography
                          variant="caption"
                          color="text.secondary"
                          noWrap
                          component="div"
                        >
                          {row.description}
                        </Typography>
                      )}
                    </Box>
                    <Chip
                      size="small"
                      variant="outlined"
                      label={row.source}
                      sx={{ display: { xs: 'none', sm: 'inline-flex' } }}
                    />
                    <Tooltip title="Move up">
                      <span>
                        <IconButton
                          size="small"
                          aria-label={`Move ${row.label} up`}
                          disabled={disabled || index === 0}
                          onClick={() =>
                            commit(moveSection(rows, index, index - 1))
                          }
                        >
                          <CippIcons.KeyboardArrowUp fontSize="small" />
                        </IconButton>
                      </span>
                    </Tooltip>
                    <Tooltip title="Move down">
                      <span>
                        <IconButton
                          size="small"
                          aria-label={`Move ${row.label} down`}
                          disabled={disabled || index === rows.length - 1}
                          onClick={() =>
                            commit(moveSection(rows, index, index + 1))
                          }
                        >
                          <CippIcons.KeyboardArrowDown fontSize="small" />
                        </IconButton>
                      </span>
                    </Tooltip>
                    <Tooltip title="Remove">
                      <span>
                        <IconButton
                          size="small"
                          aria-label={`Remove ${row.label}`}
                          disabled={disabled}
                          onClick={() => commit(removeSection(rows, index))}
                        >
                          <CippIcons.Close fontSize="small" />
                        </IconButton>
                      </span>
                    </Tooltip>
                  </Box>
                ))}
              </Paper>
            )}

            <Autocomplete
              size="small"
              options={available}
              value={null}
              inputValue={inputValue}
              onInputChange={(_, v, reason) =>
                setInputValue(reason === 'reset' ? '' : v)
              }
              onChange={(_, option) => {
                if (option) commit(addSection(rows, option))
                setInputValue('')
              }}
              groupBy={(o) => o.source}
              getOptionLabel={(o) => o?.label ?? ''}
              isOptionEqualToValue={(o, v) => o.value === v.value}
              loading={catalog.isFetching}
              disabled={disabled}
              noOptionsText={
                options.length === 0
                  ? 'Loading sections...'
                  : 'Every section is already in the list'
              }
              renderOption={(props, o) => {
                const { key, ...rest } = props
                return (
                  <li key={key} {...rest}>
                    <Box>
                      <Typography variant="body2">{o.label}</Typography>
                      {o.description && (
                        <Typography variant="caption" color="text.secondary">
                          {o.description}
                        </Typography>
                      )}
                    </Box>
                  </li>
                )
              }}
              renderInput={(params) => (
                <TextField
                  {...params}
                  label="Add a section"
                  placeholder="Built-in sections and Report Builder templates"
                />
              )}
            />
          </Stack>
        )
      }}
    />
  )
}

export default CippReportSectionsPicker
