import { CardContent } from '@mui/material'
import { Layout as DashboardLayout } from '../../../layouts/index'
import CippPageCard from '../../../components/CippCards/CippPageCard'
import { CippPasswordHandoverSettings } from '../../../addons/password-handover/CippPasswordHandoverSettings'

const Page = () => (
  <CippPageCard title="Password hand-over" hideBackButton>
    <CardContent>
      <CippPasswordHandoverSettings />
    </CardContent>
  </CippPageCard>
)

Page.getLayout = (page) => <DashboardLayout>{page}</DashboardLayout>

export default Page
