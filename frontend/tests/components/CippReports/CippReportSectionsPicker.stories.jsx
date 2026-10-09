import React from 'react'
import { http, HttpResponse } from 'msw'
import { useForm } from 'react-hook-form'
import { Box } from '@mui/material'
import { CippReportSectionsPicker } from '../../../src/components/CippReports/CippReportSectionsPicker'

const catalog = [
  {
    value: 'summary',
    label: 'Summary',
    source: 'Built-in',
    description:
      'Headline figures, overall status and the optional note from your team.',
  },
  {
    value: 'm365-security',
    label: 'Microsoft 365 security',
    source: 'Built-in',
    description: 'Secure Score with trend, and MFA coverage.',
  },
  {
    value: 'devices',
    label: 'Devices (Atera)',
    source: 'Built-in',
    description:
      'Device count, operating systems and devices needing attention.',
  },
  {
    value: 'support',
    label: 'Support requests (Atera)',
    source: 'Built-in',
    description:
      'Requests opened and resolved, time spent, and the list of requests.',
  },
  {
    value: 'recommendations',
    label: 'Recommendations',
    source: 'Built-in',
    description: 'Open pre-check items written for the customer.',
  },
  {
    value: 'template:abc',
    label: 'Backup status (Report Builder)',
    source: 'Report Builder',
    description: "A Report Builder template, filled with the company's data.",
  },
]

const handlers = [
  http.get('*/api/ListReportSections', () => HttpResponse.json(catalog)),
]

const Harness = ({ initial }) => {
  const formControl = useForm({ defaultValues: { Sections: initial } })
  return (
    <Box sx={{ maxWidth: 640, p: 2 }}>
      <CippReportSectionsPicker
        formControl={formControl}
        name="Sections"
        label="Report sections (drag to reorder)"
        helperText="The sections of this company's monthly report, top to bottom."
        emptyText="Using the default sections from Reports > Settings."
      />
    </Box>
  )
}

export default {
  title: 'Components/CippReports/CippReportSectionsPicker',
  component: CippReportSectionsPicker,
  parameters: { msw: { handlers } },
}

export const Empty = { render: () => <Harness initial={[]} /> }

export const WithSections = {
  render: () => (
    <Harness
      initial={[
        { label: 'summary', value: 'summary' },
        { label: 'template:abc', value: 'template:abc' },
        { label: 'devices', value: 'devices' },
        { label: 'template:gone (missing)', value: 'template:gone' },
        { label: 'recommendations', value: 'recommendations' },
      ]}
    />
  ),
}
