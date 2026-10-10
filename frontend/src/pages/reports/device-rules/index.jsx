import { Layout as DashboardLayout } from '../../../layouts/index'
import CippPageCard from '../../../components/CippCards/CippPageCard'
import { CardContent } from '@mui/material'
import { CippDeviceRulesTable } from '../../../components/CippReports/CippDeviceRulesTable'

const Page = () => (
  <CippPageCard
    title="Device Rules"
    hideBackButton={true}
    noTenantInHead={true}
  >
    <CardContent>
      <CippDeviceRulesTable />
    </CardContent>
  </CippPageCard>
)

Page.getLayout = (page) => <DashboardLayout>{page}</DashboardLayout>

export default Page
