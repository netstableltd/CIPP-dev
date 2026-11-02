import { CardContent } from '@mui/material'
import { Layout as DashboardLayout } from '../../../layouts/index'
import CippPageCard from '../../../components/CippCards/CippPageCard'
import { CippSharedMailboxProcess } from '../../../addons/shared-mailbox/CippSharedMailboxProcess'
import { useSettings } from '../../../hooks/use-settings'

const Page = () => {
  const tenant = useSettings().currentTenant
  return (
    <CippPageCard title="Shared mailbox" hideBackButton>
      <CardContent>
        <CippSharedMailboxProcess tenant={tenant} />
      </CardContent>
    </CippPageCard>
  )
}

Page.getLayout = (page) => <DashboardLayout>{page}</DashboardLayout>

export default Page
