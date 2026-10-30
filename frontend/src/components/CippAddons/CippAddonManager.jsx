import { useRef, useState } from 'react'
import NextLink from 'next/link'
import {
  Alert,
  Box,
  Button,
  Card,
  CardContent,
  Chip,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  Divider,
  FormControlLabel,
  Link,
  Skeleton,
  Stack,
  Switch,
  Typography,
} from '@mui/material'
import { Delete, Download, OpenInNew, UploadFile } from '@mui/icons-material'
import { ApiGetCall, ApiPostCall } from '../../api/ApiCall'
import { downloadServerPdf } from '../CippPdf/useServerPdf'

/** How each compatibility status reads and looks. */
export const addonStatusInfo = {
  Compatible: { label: 'Compatible', color: 'success' },
  Untested: { label: 'Not tested on this version', color: 'warning' },
  NeedsNewerCipp: { label: 'Needs a newer CIPP', color: 'error' },
  Problem: { label: 'Problem', color: 'error' },
}

const installedInfo = {
  New: { label: 'New add-on', color: 'info' },
  Upgrade: { label: 'Newer than installed', color: 'info' },
  Installed: { label: 'Same as installed', color: 'default' },
  Older: { label: 'Older than installed', color: 'warning' },
}

const readAsDataUrl = (file) =>
  new Promise((resolve, reject) => {
    const reader = new FileReader()
    reader.onload = () => resolve(reader.result)
    reader.onerror = () => reject(reader.error)
    reader.readAsDataURL(file)
  })

const formatBytes = (bytes) =>
  bytes > 1024 * 1024
    ? `${(bytes / 1024 / 1024).toFixed(1)} MB`
    : `${Math.max(1, Math.round((bytes || 0) / 1024))} KB`

const formatDate = (value) => (value ? new Date(value).toLocaleString() : '')

const StatusChip = ({ status }) => {
  const info = addonStatusInfo[status] || {
    label: status || 'Unknown',
    color: 'default',
  }
  return <Chip size="small" label={info.label} color={info.color} />
}

const resultText = (action) =>
  action.isError
    ? (action.error?.response?.data?.Results ?? action.error?.message)
    : action.data?.data?.Results

/** One installed add-on: what it is, whether it suits this CIPP, on/off, open and download. */
const InstalledAddon = ({ addon, latest, onToggle, busy }) => {
  const [downloadError, setDownloadError] = useState(null)
  const placement = addon.Menu?.[0]?.placement || 'Community Additions'
  const preferred = addon.Menu?.[0]?.preferredPlacement
  return (
    <Card variant="outlined" data-testid={`addon-${addon.Id}`}>
      <CardContent>
        <Stack
          direction={{ xs: 'column', sm: 'row' }}
          spacing={1}
          justifyContent="space-between"
          useFlexGap
        >
          <Box>
            <Typography variant="h6">{addon.Name}</Typography>
            <Typography variant="body2" color="text.secondary">
              Version {addon.Version}
              {addon.Author ? ` · ${addon.Author}` : ''}
              {addon.Category ? ` · ${addon.Category}` : ''}
            </Typography>
          </Box>
          <FormControlLabel
            control={
              <Switch
                checked={Boolean(addon.Enabled)}
                disabled={busy}
                onChange={(e) => onToggle(addon, e.target.checked)}
                slotProps={{
                  input: { 'aria-label': `${addon.Name} turned on` },
                }}
              />
            }
            label={addon.Enabled ? 'On' : 'Off'}
          />
        </Stack>
        {addon.Description && (
          <Typography variant="body2" sx={{ mt: 1 }}>
            {addon.Description}
          </Typography>
        )}
        <Stack
          direction="row"
          spacing={1}
          sx={{ mt: 1.5, flexWrap: 'wrap' }}
          useFlexGap
          alignItems="center"
        >
          <StatusChip status={addon.Status} />
          <Typography variant="body2" color="text.secondary">
            {addon.StatusMessage}
          </Typography>
        </Stack>
        {(addon.MissingFunctions?.length > 0 ||
          addon.MissingEndpoints?.length > 0) && (
          <Alert severity="error" sx={{ mt: 1.5 }}>
            {addon.MissingFunctions?.length > 0 && (
              <div>
                CIPP functions it needs that aren't in this version:{' '}
                {addon.MissingFunctions.join(', ')}
              </div>
            )}
            {addon.MissingEndpoints?.length > 0 && (
              <div>
                Its endpoints that didn't load:{' '}
                {addon.MissingEndpoints.join(', ')}
              </div>
            )}
          </Alert>
        )}
        <Box
          component="dl"
          sx={{
            mt: 1.5,
            mb: 0,
            display: 'grid',
            gridTemplateColumns: { sm: '200px 1fr' },
            rowGap: 0.5,
            columnGap: 2,
            '& dt': { color: 'text.secondary' },
            '& dd': { m: 0 },
          }}
        >
          <Typography component="dt" variant="body2">
            Tested on CIPP
          </Typography>
          <Typography component="dd" variant="body2">
            {(addon.TestedWith || []).join(', ')} (needs {addon.MinVersion} or
            later)
          </Typography>
          {latest && (
            <>
              <Typography component="dt" variant="body2">
                Newest CIPP ({latest})
              </Typography>
              <Typography component="dd" variant="body2">
                {addon.TestedOnLatest
                  ? 'Tested'
                  : 'Not tested yet: check it before updating CIPP'}
              </Typography>
            </>
          )}
          <Typography component="dt" variant="body2">
            In the menu
          </Typography>
          <Typography component="dd" variant="body2">
            {placement}
            {preferred && preferred !== placement
              ? ` (could later move to ${preferred})`
              : ''}
          </Typography>
          {addon.CoreChanges?.length > 0 && (
            <>
              <Typography component="dt" variant="body2">
                Changes to CIPP itself
              </Typography>
              <Typography component="dd" variant="body2">
                {addon.CoreChanges.map((c) => c.area).join('; ')}
              </Typography>
            </>
          )}
          {addon.Storage?.length > 0 && (
            <>
              <Typography component="dt" variant="body2">
                Keeps data in
              </Typography>
              <Typography component="dd" variant="body2">
                {addon.Storage.map((s) => s.table).join(', ')}
              </Typography>
            </>
          )}
        </Box>
        <Stack
          direction="row"
          spacing={1}
          sx={{ mt: 2, flexWrap: 'wrap' }}
          useFlexGap
        >
          {addon.Enabled &&
            (addon.Menu || []).map((item) => (
              <Button
                key={item.path}
                size="small"
                variant="outlined"
                startIcon={<OpenInNew />}
                component={NextLink}
                href={item.path}
              >
                Open {addon.Menu.length > 1 ? item.title : ''}
              </Button>
            ))}
          <Button
            size="small"
            startIcon={<Download />}
            disabled={!addon.PackageAvailable}
            onClick={() => {
              setDownloadError(null)
              downloadServerPdf(
                `/api/ExecAddonDownload?Id=${encodeURIComponent(addon.Id)}`,
                null,
                `${addon.Id}-${addon.Version}.zip`
              ).catch(() =>
                setDownloadError("The package couldn't be downloaded.")
              )
            }}
          >
            Download package
            {addon.PackageBytes ? ` (${formatBytes(addon.PackageBytes)})` : ''}
          </Button>
        </Stack>
        {!addon.PackageAvailable && (
          <Typography
            variant="caption"
            color="text.secondary"
            component="div"
            sx={{ mt: 0.5 }}
          >
            This CIPP wasn't built with a package for it (packages are made when
            the image is built).
          </Typography>
        )}
        {downloadError && (
          <Alert severity="error" sx={{ mt: 1 }}>
            {downloadError}
          </Alert>
        )}
      </CardContent>
    </Card>
  )
}

/** The uploaded packages and the upload button. */
const Uploads = ({ uploads, limits }) => {
  const input = useRef(null)
  const [fileError, setFileError] = useState(null)
  const [downloadError, setDownloadError] = useState(null)
  const action = ApiPostCall({ relatedQueryKeys: ['ListAddons'] })
  const maxBytes = limits?.packageBytes || 10 * 1024 * 1024

  const upload = async (file) => {
    if (!file) return
    action.reset()
    setFileError(null)
    if (!/\.zip$/i.test(file.name)) {
      setFileError('Choose an add-on package (.zip).')
      return
    }
    if (file.size > maxBytes) {
      setFileError(
        `Add-on packages must be ${formatBytes(maxBytes)} or smaller.`
      )
      return
    }
    const data = await readAsDataUrl(file)
    action.mutate({
      url: '/api/ExecAddon',
      data: { Action: 'Upload', FileName: file.name, Data: data },
    })
  }
  const errors = action.error?.response?.data?.Errors
  const warnings = action.data?.data?.Warnings
  const message = fileError || resultText(action)

  return (
    <Stack spacing={1.5}>
      <Typography variant="body2" color="text.secondary">
        Upload an add-on package (.zip) to check it against this CIPP and keep
        it here. Uploading doesn&apos;t install or run anything: install it into
        the CIPP code with the add-on tools (below), so it is reviewed, tested
        and built like the rest of CIPP.
      </Typography>
      <Box>
        <input
          ref={input}
          type="file"
          accept=".zip,application/zip"
          hidden
          data-testid="addon-file"
          onChange={(e) => {
            upload(e.target.files?.[0])
            e.target.value = ''
          }}
        />
        <Button
          variant="outlined"
          startIcon={<UploadFile />}
          disabled={action.isPending}
          onClick={() => input.current?.click()}
        >
          Upload package (.zip)
        </Button>
      </Box>
      {action.isPending && <Typography variant="body2">Checking…</Typography>}
      {!action.isPending && message && (
        <Alert severity={fileError || action.isError ? 'error' : 'success'}>
          {message}
          {errors?.length > 0 && (
            <Box component="ul" sx={{ m: 0, mt: 0.5, pl: 2.5 }}>
              {errors.map((e) => (
                <li key={e}>{e}</li>
              ))}
            </Box>
          )}
          {warnings?.length > 0 && (
            <Box component="ul" sx={{ m: 0, mt: 0.5, pl: 2.5 }}>
              {warnings.map((w) => (
                <li key={w}>{w}</li>
              ))}
            </Box>
          )}
        </Alert>
      )}
      {downloadError && <Alert severity="error">{downloadError}</Alert>}
      {uploads.length === 0 ? (
        <Typography variant="body2" color="text.secondary">
          No packages uploaded.
        </Typography>
      ) : (
        uploads.map((u) => {
          const installed = installedInfo[u.Installed]
          return (
            <Card
              variant="outlined"
              key={u.RowKey}
              data-testid={`upload-${u.RowKey}`}
            >
              <CardContent sx={{ py: 1.5, '&:last-child': { pb: 1.5 } }}>
                <Stack
                  direction={{ xs: 'column', md: 'row' }}
                  spacing={1}
                  justifyContent="space-between"
                  useFlexGap
                >
                  <Box>
                    <Typography variant="subtitle1">
                      {u.Name} {u.Version}
                    </Typography>
                    <Typography variant="body2" color="text.secondary">
                      {u.FileName} · {formatBytes(u.Bytes)} · uploaded{' '}
                      {formatDate(u.UploadedAt)}
                      {u.UploadedBy ? ` by ${u.UploadedBy}` : ''}
                    </Typography>
                    <Stack
                      direction="row"
                      spacing={1}
                      sx={{ mt: 1, flexWrap: 'wrap' }}
                      useFlexGap
                      alignItems="center"
                    >
                      <StatusChip status={u.Status} />
                      {installed && (
                        <Chip
                          size="small"
                          variant="outlined"
                          color={installed.color}
                          label={
                            u.InstalledVersion && u.Installed !== 'New'
                              ? `${installed.label} (${u.InstalledVersion})`
                              : installed.label
                          }
                        />
                      )}
                      <Typography variant="body2" color="text.secondary">
                        {u.StatusMessage}
                      </Typography>
                    </Stack>
                    {u.Warnings?.length > 0 && (
                      <Typography
                        variant="caption"
                        color="text.secondary"
                        component="div"
                        sx={{ mt: 0.5 }}
                      >
                        {u.Warnings.join(' ')}
                      </Typography>
                    )}
                    <Typography
                      variant="caption"
                      color="text.secondary"
                      component="div"
                      sx={{ mt: 0.5, wordBreak: 'break-all' }}
                    >
                      SHA-256 {u.Sha256}
                    </Typography>
                  </Box>
                  <Stack
                    direction="row"
                    spacing={1}
                    alignItems="flex-start"
                    useFlexGap
                  >
                    <Button
                      size="small"
                      startIcon={<Download />}
                      onClick={() => {
                        setDownloadError(null)
                        downloadServerPdf(
                          `/api/ExecAddonDownload?RowKey=${encodeURIComponent(u.RowKey)}`,
                          null,
                          `${u.Id}-${u.Version}.zip`
                        ).catch(() =>
                          setDownloadError(
                            "The package couldn't be downloaded."
                          )
                        )
                      }}
                    >
                      Download
                    </Button>
                    <Button
                      size="small"
                      color="error"
                      startIcon={<Delete />}
                      disabled={action.isPending}
                      onClick={() =>
                        action.mutate({
                          url: '/api/ExecAddon',
                          data: { Action: 'DeleteUpload', RowKey: u.RowKey },
                        })
                      }
                    >
                      Remove
                    </Button>
                  </Stack>
                </Stack>
              </CardContent>
            </Card>
          )
        })
      )}
    </Stack>
  )
}

const Section = ({ title, children }) => (
  <Card>
    <CardContent>
      <Typography variant="h6" sx={{ mb: 1.5 }}>
        {title}
      </Typography>
      {children}
    </CardContent>
  </Card>
)

/**
 * Community Additions > Settings > Add-ons: the installed add-ons (turn on/off, compatibility with this
 * CIPP and the newest one, download), uploaded packages, and how add-ons are installed and checked.
 */
export const CippAddonManager = () => {
  const list = ApiGetCall({ url: '/api/ListAddons', queryKey: 'ListAddons' })
  const toggle = ApiPostCall({
    relatedQueryKeys: ['ListAddons', 'featureFlags'],
  })
  const [confirm, setConfirm] = useState(null)
  const data = list.data
  const addons = data?.Addons || []
  const uploads = data?.Uploads || []
  const latest = data?.LatestCippVersion
  const newer =
    latest &&
    data?.CippVersion &&
    latest.localeCompare(data.CippVersion, undefined, { numeric: true }) > 0

  const setEnabled = (addon, enabled) => {
    if (!enabled) {
      setConfirm(addon)
      return
    }
    toggle.mutate({
      url: '/api/ExecAddon',
      data: { Action: 'Enable', Id: addon.Id },
    })
  }

  return (
    <Stack spacing={2}>
      {list.isLoading && <Skeleton variant="rounded" height={160} />}
      {list.isError && (
        <Alert severity="error">The add-ons couldn&apos;t be loaded.</Alert>
      )}
      {data && (
        <Alert severity={newer ? 'info' : 'success'} icon={false}>
          This CIPP is version <strong>{data.CippVersion || 'unknown'}</strong>.{' '}
          {latest
            ? newer
              ? `CIPP ${latest} is out: check the add-ons against it before updating (see below).`
              : 'It is the newest CIPP version.'
            : "The newest CIPP version couldn't be checked."}
        </Alert>
      )}
      {!toggle.isPending && resultText(toggle) && (
        <Alert
          severity={toggle.isError ? 'error' : 'success'}
          onClose={() => toggle.reset()}
        >
          {resultText(toggle)}
        </Alert>
      )}
      {data && (
        <Section title="Installed add-ons">
          {addons.length === 0 ? (
            <Typography variant="body2" color="text.secondary">
              No add-ons are installed.
            </Typography>
          ) : (
            <Stack spacing={1.5}>
              {addons.map((addon) => (
                <InstalledAddon
                  key={addon.Id}
                  addon={addon}
                  latest={latest}
                  busy={toggle.isPending}
                  onToggle={setEnabled}
                />
              ))}
            </Stack>
          )}
        </Section>
      )}
      {data && (
        <Section title="Uploaded packages">
          <Uploads uploads={uploads} limits={data.Limits} />
        </Section>
      )}
      <Section title="Installing, removing and checking add-ons">
        <Typography variant="body2" component="div">
          Add-ons are part of the CIPP code, so they go through the same review,
          tests and build. From a copy of the CIPP repository:
          <Box
            component="ul"
            sx={{ mt: 1, mb: 1, pl: 2.5, '& code': { fontSize: '0.85em' } }}
          >
            <li>
              <strong>Install or upgrade:</strong> download the package, then
              run{' '}
              <code>
                build/tools/addons/Install-CippAddon.ps1 -Path package.zip
              </code>{' '}
              (add <code>-Upgrade</code> to replace an installed version).
              Commit and push; the add-on appears once the new image is running.
            </li>
            <li>
              <strong>Remove:</strong>{' '}
              <code>
                build/tools/addons/Uninstall-CippAddon.ps1 -Id &lt;id&gt;
              </code>
              , then commit and push. To hide one without removing it, turn it
              off here.
            </li>
            <li>
              <strong>Before updating CIPP:</strong> fetch the new version, then
              run{' '}
              <code>
                build/tools/addons/Test-CippAddonUpstream.ps1 -Ref upstream/main
              </code>
              . It lists what each add-on uses from CIPP that has changed or
              gone. After testing, add the new version to{' '}
              <code>cipp.testedWith</code> in the add-on&apos;s addon.json.
            </li>
            <li>
              <strong>Make a package</strong> from the code:{' '}
              <code>
                build/tools/addons/Export-CippAddon.ps1 -Id &lt;id&gt;
              </code>
              .
            </li>
          </Box>
          <Link
            href="https://docs.cipp.app/user-documentation/community/settings/addons"
            target="_blank"
            rel="noopener"
          >
            How add-ons work
          </Link>
        </Typography>
      </Section>

      <Dialog open={Boolean(confirm)} onClose={() => setConfirm(null)}>
        <DialogTitle>Turn off {confirm?.Name}?</DialogTitle>
        <DialogContent>
          <Typography variant="body2">
            Its pages leave the menu and its API calls are refused until it is
            turned back on. Nothing is deleted.
          </Typography>
        </DialogContent>
        <Divider />
        <DialogActions>
          <Button onClick={() => setConfirm(null)}>Cancel</Button>
          <Button
            color="error"
            variant="contained"
            onClick={() => {
              toggle.mutate({
                url: '/api/ExecAddon',
                data: { Action: 'Disable', Id: confirm.Id },
              })
              setConfirm(null)
            }}
          >
            Turn off
          </Button>
        </DialogActions>
      </Dialog>
    </Stack>
  )
}
