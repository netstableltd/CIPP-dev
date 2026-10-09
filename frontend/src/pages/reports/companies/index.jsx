import { CippTablePage } from '../../../components/CippComponents/CippTablePage.jsx'
import { CippIcons } from '../../../utils/icon-registry'
import { Layout as DashboardLayout } from '../../../layouts/index'

const deliveryOptions = [
  { label: 'Default (from Reports settings)', value: 'Default' },
  { label: 'Review then send', value: 'Review' },
  { label: 'Send automatically', value: 'Auto' },
  { label: 'Manual only', value: 'Manual' },
]

const scheduleOptions = [
  { label: 'Default (from Reports settings)', value: 'Default' },
  { label: 'Custom day of month', value: 'Custom' },
  { label: 'Manual only (Test button)', value: 'Manual' },
  { label: 'Paused until a date', value: 'Paused' },
]

const editFields = [
  {
    type: 'switch',
    name: 'Enabled',
    label: 'Produce monthly reports for this company',
  },
  {
    type: 'textField',
    name: 'Recipients',
    label: 'Customer report recipients (comma separated)',
    helperText:
      'Who receives the customer report. Nothing is sent to customers while "Allow sending" is off in Reports > Settings.',
  },
  {
    type: 'textField',
    name: 'PrecheckRecipients',
    label: 'Pre-check recipients (optional override)',
    helperText: 'Leave blank to use the address in Reports > Settings.',
  },
  {
    type: 'autoComplete',
    name: 'DeliveryMode',
    label: 'Delivery',
    multiple: false,
    creatable: false,
    options: deliveryOptions,
  },
  {
    type: 'autoComplete',
    name: 'ScheduleMode',
    label: 'Schedule',
    multiple: false,
    creatable: false,
    options: scheduleOptions,
  },
  {
    type: 'textField',
    name: 'ReportDay',
    label: 'Report day of month (1-28)',
    condition: {
      field: 'ScheduleMode',
      compareType: 'valueEq',
      compareValue: 'Custom',
    },
  },
  {
    type: 'textField',
    name: 'PausedUntil',
    label: 'Paused until (YYYY-MM-DD)',
    condition: {
      field: 'ScheduleMode',
      compareType: 'valueEq',
      compareValue: 'Paused',
    },
  },
  {
    type: 'textField',
    name: 'Notes',
    label: 'Internal notes',
    multiline: true,
    rows: 3,
  },
]

const Page = () => {
  const actions = [
    {
      label: 'Edit report settings',
      type: 'POST',
      url: '/api/ExecReportCompany',
      icon: <CippIcons.Edit />,
      data: { TenantId: 'TenantId' },
      fields: editFields,
      setDefaultValues: true,
      confirmText: 'Report settings for [displayName]',
      multiPost: false,
    },
    {
      label: 'Turn reporting on',
      type: 'POST',
      url: '/api/ExecReportCompany',
      icon: <CippIcons.CheckCircle />,
      data: { TenantId: 'TenantId', Action: 'Enable' },
      confirmText: 'Turn monthly reporting on for the selected companies?',
      multiPost: false,
    },
    {
      label: 'Turn reporting off',
      type: 'POST',
      url: '/api/ExecReportCompany',
      icon: <CippIcons.Block />,
      data: { TenantId: 'TenantId', Action: 'Disable' },
      confirmText: 'Turn monthly reporting off for the selected companies?',
      multiPost: false,
    },
  ]

  const offCanvas = {
    extendedInfoFields: [
      'displayName',
      'defaultDomainName',
      'Enabled',
      'Recipients',
      'EffectivePrecheckRecipients',
      'EffectiveDeliveryMode',
      'ScheduleMode',
      'ReportDay',
      'PausedUntil',
      'AteraCustomer',
      'DataStatus',
      'Notes',
      'LastModifiedBy',
    ],
    actions,
  }

  return (
    <CippTablePage
      title="Report Companies"
      tenantInTitle={false}
      apiUrl="/api/ListReportCompanies"
      queryKey="ListReportCompanies"
      simpleColumns={[
        'displayName',
        'Enabled',
        'EffectiveDeliveryMode',
        'ScheduleMode',
        'Recipients',
        'AteraCustomer',
        'DataStatus',
      ]}
      actions={actions}
      offCanvas={offCanvas}
    />
  )
}

Page.getLayout = (page) => <DashboardLayout>{page}</DashboardLayout>

export default Page
