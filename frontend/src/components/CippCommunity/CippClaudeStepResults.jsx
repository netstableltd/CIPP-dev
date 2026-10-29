import {
  Alert,
  CircularProgress,
  List,
  ListItem,
  ListItemIcon,
  ListItemText,
  Stack,
  Typography,
} from '@mui/material'
import {
  CheckCircle,
  Error as ErrorIcon,
  Info as InfoIcon,
  Warning,
} from '@mui/icons-material'

const statusIcon = {
  Success: <CheckCircle color="success" fontSize="small" />,
  Info: <InfoIcon color="info" fontSize="small" />,
  Warning: <Warning color="warning" fontSize="small" />,
  Error: <ErrorIcon color="error" fontSize="small" />,
}

/** The steps an ExecClaudeConnector call reports (Step, Status, Message), or its error. */
export const CippClaudeStepResults = ({ action }) => {
  if (action.isPending) {
    return (
      <Stack direction="row" spacing={1} alignItems="center" sx={{ mt: 2 }}>
        <CircularProgress size={18} />
        <Typography variant="body2">Working…</Typography>
      </Stack>
    )
  }
  if (action.isError) {
    const msg = action.error?.response?.data?.Results ?? action.error?.message
    return (
      <Alert severity="error" sx={{ mt: 2 }}>
        {String(msg)}
      </Alert>
    )
  }
  const steps = action.data?.data?.Results
  if (!Array.isArray(steps) || steps.length === 0) return null
  return (
    <List dense sx={{ mt: 1 }} aria-label="What was done">
      {steps.map((s, i) => (
        <ListItem
          key={i}
          disableGutters
          sx={{ py: 0.25, alignItems: 'flex-start' }}
        >
          <ListItemIcon sx={{ minWidth: 32, mt: 0.5 }}>
            {statusIcon[s.Status] ?? null}
          </ListItemIcon>
          <ListItemText primary={s.Message} secondary={s.Step} />
        </ListItem>
      ))}
    </List>
  )
}

export default CippClaudeStepResults
