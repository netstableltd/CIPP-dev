import { CippTablePage } from '../../../components/CippComponents/CippTablePage.jsx'
import { CippIcons } from '../../../utils/icon-registry'
import { Layout as DashboardLayout } from '../../../layouts/index'
import { CippReportSectionsPicker } from '../../../components/CippReports/CippReportSectionsPicker'

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
    // Rendered by the sortable picker; declared as autoComplete so the edit dialog pre-fills
    // it from the row's Sections ([{ label, value }]).
    type: 'autoComplete',
    name: 'Sections',
    component: CippReportSectionsPicker,
    label: 'Report sections (drag to reorder)',
    helperText:
      "The sections of this company's monthly report, top to bottom: built-in sections and any template from the Report Builder. Leave empty to use the default sections from Reports > Settings.",
    emptyText: 'Using the default sections from Reports > Settings.',
  },
  {
    type: 'textField',
    name: 'Notes',
    label: 'Internal notes',
    multiline: true,
    rows: 3,
  },
]

const periodOptions = [
  { label: 'Last month', value: 'LastMonth' },
  { label: 'This month so far', value: 'ThisMonth' },
]

const testFields = [
  {
    type: 'textField',
    name: 'SendTo',
    label: 'Send to (optional, comma separated)',
    placeholder: 'you@yourcompany.com',
    helperText:
      "Only these addresses receive the test - never the company's customer recipients. Leave blank to just generate it (it appears under Generated Reports).",
  },
  {
    type: 'autoComplete',
    name: 'Period',
    label: 'Period',
    multiple: false,
    creatable: true,
    options: periodOptions,
    helperText: 'Or type a month as YYYY-MM.',
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
      label: 'Test customer report',
      type: 'POST',
      url: '/api/ExecReportTestRun',
      icon: <CippIcons.Assessment />,
      data: { TenantId: 'TenantId', ReportType: 'Customer' },
      fields: testFields,
      confirmText:
        'Generate a TEST customer report for [displayName]? It is marked TEST and only goes to the addresses you enter.',
      multiPost: false,
    },
    {
      label: 'Test pre-check',
      type: 'POST',
      url: '/api/ExecReportTestRun',
      icon: <CippIcons.FactCheck />,
      data: { TenantId: 'TenantId', ReportType: 'Precheck' },
      fields: testFields,
      confirmText: 'Run the pre-check for [displayName] now?',
      multiPost: false,
    },
    {
      label: 'Set report sections',
      type: 'POST',
      url: '/api/ExecReportCompany',
      icon: <CippIcons.ViewList />,
      data: { TenantId: 'TenantId' },
      fields: editFields.filter((f) => f.name === 'Sections'),
      confirmText:
        'Set the report sections for the selected companies. Any list they already have is replaced; leave it empty to put them back on the default sections.',
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
      'SectionsSummary',
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
        'SectionsSummary',
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
