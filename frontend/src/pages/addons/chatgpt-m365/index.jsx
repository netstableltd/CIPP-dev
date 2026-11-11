import { CardContent } from '@mui/material'
import { Layout as DashboardLayout } from '../../../layouts/index'
import CippPageCard from '../../../components/CippCards/CippPageCard'
import { CippChatGPTConnectorProcess } from '../../../addons/chatgpt-m365/CippChatGPTConnectorProcess'
import { useSettings } from '../../../hooks/use-settings'

const Page = () => {
  const tenant = useSettings().currentTenant
  return (
    <CippPageCard title="ChatGPT for Microsoft 365" hideBackButton>
      <CardContent>
        <CippChatGPTConnectorProcess tenant={tenant} />
      </CardContent>
    </CippPageCard>
  )
}

Page.getLayout = (page) => <DashboardLayout>{page}</DashboardLayout>

export default Page
