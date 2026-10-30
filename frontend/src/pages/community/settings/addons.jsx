import { Box, Container, Stack, Typography } from '@mui/material'
import { Layout as DashboardLayout } from '../../../layouts/index'
import { CippHead } from '../../../components/CippComponents/CippHead'
import { CippAddonManager } from '../../../components/CippAddons/CippAddonManager'

const Page = () => (
  <>
    <CippHead title="Add-ons" noTenant={true} />
    <Box sx={{ flexGrow: 1, pb: { xs: 2, md: 4 } }}>
      <Container maxWidth="lg" sx={{ px: { xs: 1.5, md: 3 } }}>
        <Stack spacing={2}>
          <div>
            <Typography variant="h4">Add-ons</Typography>
            <Typography color="text.secondary" sx={{ mt: 1, maxWidth: 760 }}>
              Community Additions are packaged as add-ons: each one is a set of
              pages and functions with a manifest saying which CIPP versions it
              has been tested on. Turn them on and off, check them against this
              CIPP, and upload or download packages.
            </Typography>
          </div>
          <CippAddonManager />
        </Stack>
      </Container>
    </Box>
  </>
)

Page.getLayout = (page) => <DashboardLayout>{page}</DashboardLayout>

export default Page
