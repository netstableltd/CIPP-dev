import { useRef, useState } from 'react'
import {
  Alert,
  Box,
  Button,
  FormControlLabel,
  Stack,
  Switch,
  Typography,
} from '@mui/material'
import { Delete, UploadFile } from '@mui/icons-material'
import { ApiPostCall } from '../../api/ApiCall'

const MAX_BYTES = 10 * 1024 * 1024

const readAsDataUrl = (file) =>
  new Promise((resolve, reject) => {
    const reader = new FileReader()
    reader.onload = () => resolve(reader.result)
    reader.onerror = () => reject(reader.error)
    reader.readAsDataURL(file)
  })

/**
 * An add-on's how-to guide: the MSP's own Word document (one of the guides in the add-on's addon.json),
 * uploaded to this CIPP instance (ExecAddonGuide) and added to the end of a customer PDF, with a switch
 * to leave it out.
 */
export const CippAddonGuideUpload = ({
  addonId,
  guideKey,
  title,
  description,
  guide,
  include,
  onIncludeChange,
  includeLabel = 'Add the guide to the end of the PDF',
  relatedQueryKeys = [],
}) => {
  const input = useRef(null)
  const action = ApiPostCall({ relatedQueryKeys })
  const [fileError, setFileError] = useState(null)

  const upload = async (file) => {
    if (!file) return
    action.reset()
    setFileError(null)
    if (!/\.docx$/i.test(file.name)) {
      setFileError('Choose a Word document (.docx).')
      return
    }
    if (file.size > MAX_BYTES) {
      setFileError('The guide must be 10 MB or smaller.')
      return
    }
    const data = await readAsDataUrl(file)
    action.mutate({
      url: '/api/ExecAddonGuide',
      data: {
        AddonId: addonId,
        Key: guideKey,
        Action: 'Upload',
        FileName: file.name,
        Data: data,
      },
    })
  }

  const message = fileError
    ? fileError
    : action.isError
      ? (action.error?.response?.data?.Results ?? action.error?.message)
      : action.data?.data?.Results

  return (
    <Box>
      <Typography variant="subtitle2">{title}</Typography>
      {description && (
        <Typography variant="body2" color="text.secondary" sx={{ mb: 1 }}>
          {description}
        </Typography>
      )}
      <Stack
        direction="row"
        spacing={1.5}
        useFlexGap
        alignItems="center"
        sx={{ flexWrap: 'wrap' }}
      >
        {guide ? (
          <Typography variant="body2">
            <strong>{guide.FileName}</strong>
            {guide.Title ? ` (${guide.Title})` : ''}
            {guide.UploadedAt
              ? `, uploaded ${new Date(guide.UploadedAt).toLocaleDateString()}`
              : ''}
            {guide.UploadedBy ? ` by ${guide.UploadedBy}` : ''}
          </Typography>
        ) : (
          <Typography variant="body2" color="text.secondary">
            No guide uploaded yet.
          </Typography>
        )}
        <input
          ref={input}
          type="file"
          accept=".docx,application/vnd.openxmlformats-officedocument.wordprocessingml.document"
          hidden
          data-testid={`guide-file-${guideKey}`}
          onChange={(e) => {
            upload(e.target.files?.[0])
            e.target.value = ''
          }}
        />
        <Button
          size="small"
          variant="outlined"
          startIcon={<UploadFile />}
          disabled={action.isPending}
          onClick={() => input.current?.click()}
        >
          {guide ? 'Replace guide' : 'Upload guide (.docx)'}
        </Button>
        {guide && (
          <Button
            size="small"
            color="error"
            startIcon={<Delete />}
            disabled={action.isPending}
            onClick={() =>
              action.mutate({
                url: '/api/ExecAddonGuide',
                data: { AddonId: addonId, Key: guideKey, Action: 'Remove' },
              })
            }
          >
            Remove
          </Button>
        )}
      </Stack>
      {guide && onIncludeChange && (
        <FormControlLabel
          sx={{ mt: 1 }}
          control={
            <Switch
              checked={include}
              onChange={(e) => onIncludeChange(e.target.checked)}
            />
          }
          label={includeLabel}
        />
      )}
      {action.isPending && (
        <Typography variant="body2" sx={{ mt: 1 }}>
          Working…
        </Typography>
      )}
      {!action.isPending && message && (
        <Alert
          severity={fileError || action.isError ? 'error' : 'success'}
          sx={{ mt: 1 }}
        >
          {String(message)}
        </Alert>
      )}
    </Box>
  )
}

export default CippAddonGuideUpload
