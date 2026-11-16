// What a customer report covers. Values match Get-CIPPReportPeriod / Resolve-CIPPReportPeriodRequest.

// A company's usual period (Reports > Companies) and the default (Reports > Settings).
export const reportCoverOptions = [
  { label: 'Previous calendar month (1st to last day)', value: 'LastMonth' },
  {
    label: 'One month up to yesterday (for mid-month reports)',
    value: 'RollingMonth',
  },
  { label: 'Last 30 days', value: 'Last30Days' },
]

// Periods for a draft or test made on request.
export const reportRunPeriodOptions = [
  { label: "Company's usual period", value: 'Scheduled' },
  { label: 'Previous calendar month', value: 'LastMonth' },
  { label: 'One month up to yesterday', value: 'RollingMonth' },
  { label: 'Last 7 days', value: 'Last7Days' },
  { label: 'Last 30 days', value: 'Last30Days' },
  { label: 'Last 90 days', value: 'Last90Days' },
  { label: 'This month so far', value: 'ThisMonth' },
  { label: 'Custom dates', value: 'Custom' },
]

const customOnly = {
  field: 'Period',
  compareType: 'valueEq',
  compareValue: 'Custom',
}

// Period picker plus start and end dates shown for "Custom dates".
export const reportRunPeriodFields = [
  {
    type: 'autoComplete',
    name: 'Period',
    label: 'Period',
    multiple: false,
    creatable: true,
    options: reportRunPeriodOptions,
    helperText:
      "Leave blank for the company's usual period. You can also type a month as YYYY-MM.",
  },
  {
    type: 'datePicker',
    name: 'StartDate',
    label: 'First day',
    dateTimeType: 'date',
    format: 'dd/MM/yyyy',
    condition: customOnly,
  },
  {
    type: 'datePicker',
    name: 'EndDate',
    label: 'Last day (included)',
    dateTimeType: 'date',
    format: 'dd/MM/yyyy',
    condition: customOnly,
  },
]
