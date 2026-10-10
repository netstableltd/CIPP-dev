import { useRouter } from 'next/router'
import { Box, Container, IconButton, Stack, Typography } from '@mui/material'
import { Layout as DashboardLayout } from '../../../../layouts/index'
import { CippHead } from '../../../../components/CippComponents/CippHead'
import { CippReportDraftEditor } from '../../../../components/CippReports/CippReportDraftEditor'
import { CippIcons } from '../../../../utils/icon-registry'

const Page = () => {
  const router = useRouter()
  const id = router.isReady ? router.query.id : null
  const back = () => router.push('/reports/review')
  return (
    <>
      <CippHead title="Review Report" noTenant={true} />
      <Box sx={{ flexGrow: 1, py: 2 }}>
        <Container maxWidth={false}>
          <Stack spacing={2}>
            <Stack direction="row" spacing={1} sx={{ alignItems: 'center' }}>
              <IconButton
                size="small"
                onClick={back}
                aria-label="Back to Review Reports"
              >
                <CippIcons.ArrowBack />
              </IconButton>
              <Typography variant="h4">Review Report</Typography>
            </Stack>
            {router.isReady && (
              <CippReportDraftEditor id={id} onClosed={back} />
            )}
          </Stack>
        </Container>
      </Box>
    </>
  )
}

Page.getLayout = (page) => <DashboardLayout>{page}</DashboardLayout>

export default Page
