import { CardContent } from '@mui/material'
import { Layout as DashboardLayout } from '../../../layouts/index'
import CippPageCard from '../../../components/CippCards/CippPageCard'
import { CippClaudeConnectorProcess } from '../../../addons/claude-m365/CippClaudeConnectorProcess'
import { useSettings } from '../../../hooks/use-settings'

const Page = () => {
  const tenant = useSettings().currentTenant
  return (
    <CippPageCard title="Claude for Microsoft 365" hideBackButton>
      <CardContent>
        <CippClaudeConnectorProcess tenant={tenant} />
      </CardContent>
    </CippPageCard>
  )
}

Page.getLayout = (page) => <DashboardLayout>{page}</DashboardLayout>

export default Page
