import { CippTablePage } from '../../../components/CippComponents/CippTablePage.jsx'
import { CippIcons } from '../../../utils/icon-registry'
import { Layout as DashboardLayout } from '../../../layouts/index'

// Customer report drafts: review, change, approve and send. Drafts are created from
// Reports > Companies ("Create draft for review").
const Page = () => {
  const actions = [
    {
      label: 'Review and edit',
      icon: <CippIcons.Edit />,
      link: '/reports/review/edit?id=[Id]',
      pinned: true,
      noConfirm: true,
    },
    {
      label: 'Approve',
      type: 'POST',
      url: '/api/ExecReportDraft',
      icon: <CippIcons.CheckCircle />,
      data: { Action: '!Approve', Id: 'Id' },
      confirmText:
        'Approve the [PeriodLabel] report for [Company] as it is now?',
      condition: (row) => row.Status === 'Draft',
      multiPost: false,
    },
    {
      label: 'Send to customer',
      type: 'POST',
      url: '/api/ExecReportDraft',
      icon: <CippIcons.Send />,
      data: { Action: '!Send', Id: 'Id' },
      confirmText:
        "Email the approved [PeriodLabel] report to [Company]'s report recipients now?",
      condition: (row) => row.Status === 'Approved',
      multiPost: false,
    },
    {
      label: 'Discard draft',
      type: 'POST',
      url: '/api/ExecReportDraft',
      icon: <CippIcons.Delete />,
      data: { Action: '!Discard', Id: 'Id' },
      confirmText:
        'Discard the [PeriodLabel] draft for [Company]? Your changes to it are lost.',
      condition: (row) => row.Status !== 'Sent',
      multiPost: false,
    },
  ]

  return (
    <CippTablePage
      title="Review Reports"
      tenantInTitle={false}
      apiUrl="/api/ListReportDrafts"
      queryKey="ListReportDrafts"
      simpleColumns={[
        'Company',
        'PeriodLabel',
        'Status',
        'Recommendations',
        'Changes',
        'GeneratedAt',
        'ApprovedBy',
        'SentAt',
      ]}
      actions={actions}
      offCanvas={{
        extendedInfoFields: [
          'Company',
          'PeriodLabel',
          'Status',
          'GeneratedBy',
          'GeneratedAt',
          'ApprovedBy',
          'ApprovedAt',
          'SentTo',
          'SentAt',
        ],
        actions,
      }}
    />
  )
}

Page.getLayout = (page) => <DashboardLayout>{page}</DashboardLayout>

export default Page
