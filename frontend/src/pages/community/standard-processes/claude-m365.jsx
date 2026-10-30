import { useEffect } from 'react'
import { useRouter } from 'next/router'

// Fork: the Claude for Microsoft 365 process moved to /addons/claude-m365 when it became an add-on. Kept
// so old links and bookmarks still work; remove once nobody uses them.
const Page = () => {
  const router = useRouter()
  useEffect(() => {
    router.replace({ pathname: '/addons/claude-m365', query: router.query })
  }, [router])
  return null
}

export default Page
