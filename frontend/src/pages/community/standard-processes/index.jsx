import { useEffect } from 'react'
import { useRouter } from 'next/router'

// Fork: Standard Processes became add-ons (Community Additions > Settings > Add-ons). Kept so old links
// and bookmarks still land somewhere; remove once nobody uses them.
const Page = () => {
  const router = useRouter()
  useEffect(() => {
    router.replace('/community/settings/addons')
  }, [router])
  return null
}

export default Page
