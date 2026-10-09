import { useEffect } from 'react'
import { Alert, Box, Typography } from '@mui/material'
import { Grid } from '@mui/system'
import { useForm } from 'react-hook-form'
import { Layout as DashboardLayout } from '../../../layouts/index'
import CippFormPage from '../../../components/CippFormPages/CippFormPage'
import CippFormComponent from '../../../components/CippComponents/CippFormComponent'
import { CippFormCondition } from '../../../components/CippComponents/CippFormCondition'
import { ApiGetCall } from '../../../api/ApiCall'
import { CippReportSectionsPicker } from '../../../components/CippReports/CippReportSectionsPicker'

const reportDayModes = [
  { label: 'First working day of the month', value: 'FirstWorkingDay' },
  { label: 'Fixed day of the month', value: 'DayOfMonth' },
]

const deliveryModes = [
  {
    label: 'Review then send (a person approves each report)',
    value: 'Review',
  },
  { label: 'Send automatically', value: 'Auto' },
  { label: 'Manual only (nothing runs until someone clicks)', value: 'Manual' },
]

const timeZones = [
  'Europe/London',
  'Europe/Dublin',
  'Europe/Amsterdam',
  'Europe/Berlin',
  'UTC',
  'America/New_York',
  'America/Chicago',
  'America/Los_Angeles',
  'Australia/Sydney',
].map((tz) => ({ label: tz, value: tz }))

const toOption = (options, value) =>
  options.find((o) => o.value === value) ||
  (value ? { label: value, value } : null)

const Page = () => {
  const formControl = useForm({ mode: 'onChange' })

  const settings = ApiGetCall({
    url: '/api/ListReportSettings',
    queryKey: 'ListReportSettings',
  })

  useEffect(() => {
    if (settings.isSuccess && settings.data) {
      const s = settings.data
      formControl.reset({
        PrecheckRecipients: s.PrecheckRecipients,
        PrecheckLeadDays: s.PrecheckLeadDays,
        ReportDayMode: toOption(reportDayModes, s.ReportDayMode),
        ReportDay: s.ReportDay,
        SendTime: s.SendTime,
        TimeZone: toOption(timeZones, s.TimeZone),
        DefaultDeliveryMode: toOption(deliveryModes, s.DefaultDeliveryMode),
        CustomerSendEnabled: Boolean(s.CustomerSendEnabled),
        // Labels come from the section catalog inside the picker.
        DefaultSections: (s.DefaultSections || []).map((id) => ({
          label: id,
          value: id,
        })),
      })
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [settings.isSuccess, settings.dataUpdatedAt])

  const loading = settings.isFetching

  return (
    <CippFormPage
      title="Report Settings"
      hideBackButton={true}
      hidePageType={true}
      formControl={formControl}
      resetForm={false}
      postUrl="/api/ExecReportSettings"
      queryKey={'ListReportSettings'}
    >
      <Box sx={{ my: 2 }}>
        <Grid container spacing={2}>
          <Grid size={{ xs: 12 }}>
            <Typography variant="h6">Internal pre-check</Typography>
            <Typography variant="body2" color="text.secondary">
              A few days before customer reports are due, CIPP checks everything
              that will go into them and sends the findings to these addresses
              so problems can be fixed first.
            </Typography>
          </Grid>
          <Grid size={{ xs: 12, md: 8 }}>
            <CippFormComponent
              type="textField"
              label="Pre-check recipients (comma separated)"
              name="PrecheckRecipients"
              disabled={loading}
              formControl={formControl}
              helperText="Default for all companies. Can be overridden per company."
            />
          </Grid>
          <Grid size={{ xs: 12, md: 4 }}>
            <CippFormComponent
              type="number"
              label="Pre-check lead time (days before report day)"
              name="PrecheckLeadDays"
              disabled={loading}
              formControl={formControl}
              validators={{
                min: { value: 1, message: 'At least 1 day' },
                max: { value: 20, message: 'At most 20 days' },
              }}
            />
          </Grid>

          <Grid size={{ xs: 12 }}>
            <Typography variant="h6" sx={{ mt: 2 }}>
              Customer report schedule (defaults)
            </Typography>
            <Typography variant="body2" color="text.secondary">
              Defaults for every company. Each company can use these, its own
              schedule, or manual only.
            </Typography>
          </Grid>
          <Grid size={{ xs: 12, md: 6 }}>
            <CippFormComponent
              type="autoComplete"
              label="Report day"
              name="ReportDayMode"
              multiple={false}
              creatable={false}
              options={reportDayModes}
              disabled={loading}
              formControl={formControl}
            />
          </Grid>
          <CippFormCondition
            field="ReportDayMode"
            compareType="valueEq"
            compareValue="DayOfMonth"
            formControl={formControl}
            clearOnHide={false}
          >
            <Grid size={{ xs: 12, md: 6 }}>
              <CippFormComponent
                type="number"
                label="Day of month (1-28)"
                name="ReportDay"
                disabled={loading}
                formControl={formControl}
                validators={{
                  min: { value: 1, message: 'Between 1 and 28' },
                  max: { value: 28, message: 'Between 1 and 28' },
                }}
              />
            </Grid>
          </CippFormCondition>
          <Grid size={{ xs: 12, md: 3 }}>
            <CippFormComponent
              type="textField"
              label="Send time (HH:mm)"
              name="SendTime"
              disabled={loading}
              formControl={formControl}
              validators={{
                pattern: {
                  value: /^([01]\d|2[0-3]):[0-5]\d$/,
                  message: '24-hour time, e.g. 09:00',
                },
              }}
            />
          </Grid>
          <Grid size={{ xs: 12, md: 3 }}>
            <CippFormComponent
              type="autoComplete"
              label="Time zone"
              name="TimeZone"
              multiple={false}
              creatable={true}
              options={timeZones}
              disabled={loading}
              formControl={formControl}
            />
          </Grid>
          <Grid size={{ xs: 12, md: 6 }}>
            <CippFormComponent
              type="autoComplete"
              label="Default delivery"
              name="DefaultDeliveryMode"
              multiple={false}
              creatable={false}
              options={deliveryModes}
              disabled={loading}
              formControl={formControl}
            />
          </Grid>

          <Grid size={{ xs: 12 }}>
            <Typography variant="h6" sx={{ mt: 2 }}>
              Report sections (default)
            </Typography>
            <Typography variant="body2" color="text.secondary">
              The sections in each company&apos;s monthly report, in order. Use
              the built-in sections and any template designed in the Report
              Builder (Reports &gt; Report Builder). A company can choose its
              own list under Reports &gt; Companies. Leave empty for all
              built-in sections.
            </Typography>
          </Grid>
          <Grid size={{ xs: 12 }}>
            <CippReportSectionsPicker
              formControl={formControl}
              name="DefaultSections"
              label="Default report sections (drag to reorder)"
              emptyText="No default chosen: reports include every built-in section."
              disabled={loading}
            />
          </Grid>

          <Grid size={{ xs: 12 }}>
            <Typography variant="h6" sx={{ mt: 2 }}>
              Sending to customers
            </Typography>
          </Grid>
          <Grid size={{ xs: 12 }}>
            <Alert severity="warning" sx={{ mb: 1 }}>
              While this is off, no report is ever sent to a customer recipient.
              Pre-checks and Test sends to an address you type still work. Leave
              it off on test or development instances.
            </Alert>
            <CippFormComponent
              type="switch"
              label="Allow sending reports to customer recipients"
              name="CustomerSendEnabled"
              disabled={loading}
              formControl={formControl}
            />
          </Grid>
          {settings.data?.LastModifiedBy && (
            <Grid size={{ xs: 12 }}>
              <Typography variant="caption" color="text.secondary">
                Last saved by {settings.data.LastModifiedBy}
                {settings.data.LastModified
                  ? ` on ${new Date(settings.data.LastModified).toLocaleString()}`
                  : ''}
              </Typography>
            </Grid>
          )}
        </Grid>
      </Box>
    </CippFormPage>
  )
}

Page.getLayout = (page) => <DashboardLayout>{page}</DashboardLayout>

export default Page
