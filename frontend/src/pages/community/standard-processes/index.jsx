import NextLink from 'next/link'
import {
  Box,
  Button,
  Card,
  CardActions,
  CardContent,
  Chip,
  Container,
  Grid,
  Stack,
  Typography,
} from '@mui/material'
import { Layout as DashboardLayout } from '../../../layouts/index'
import { CippHead } from '../../../components/CippComponents/CippHead'
import { standardProcesses } from '../../../data/standardProcesses'
import { usePermissions } from '../../../hooks/use-permissions'

const Page = () => {
  const { checkPermissions, isLoading } = usePermissions()
  const processes = isLoading
    ? []
    : standardProcesses.filter((p) => checkPermissions(p.permissions))

  return (
    <>
      <CippHead title="Standard Processes" noTenant={true} />
      <Box sx={{ flexGrow: 1, pb: { xs: 2, md: 4 } }}>
        <Container maxWidth="xl" sx={{ px: { xs: 1.5, md: 3 } }}>
          <Stack spacing={2}>
            <div>
              <Typography variant="h4">Standard Processes</Typography>
              <Typography color="text.secondary" sx={{ mt: 1, maxWidth: 760 }}>
                Jobs we do the same way in every tenant, each as a guided page.
                Pick a tenant at the top, open a process and follow its steps.
                Every process checks what's already in place, so it's safe to
                run again.
              </Typography>
            </div>
            <Grid container spacing={2}>
              {processes.map((p) => (
                <Grid key={p.id} size={{ xs: 12, md: 6, lg: 4 }}>
                  <Card
                    sx={{
                      height: '100%',
                      display: 'flex',
                      flexDirection: 'column',
                    }}
                  >
                    <CardContent sx={{ flexGrow: 1 }}>
                      <Typography variant="h6">{p.title}</Typography>
                      <Typography color="text.secondary" sx={{ mt: 1 }}>
                        {p.summary}
                      </Typography>
                      <Box component="ol" sx={{ pl: 2.5, mt: 2, mb: 0 }}>
                        {p.steps.map((s) => (
                          <Typography
                            component="li"
                            variant="body2"
                            key={s}
                            sx={{ mb: 0.5 }}
                          >
                            {s}
                          </Typography>
                        ))}
                      </Box>
                      {p.needs && (
                        <Typography variant="body2" sx={{ mt: 1.5 }}>
                          <strong>Needs:</strong> {p.needs}
                        </Typography>
                      )}
                      <Stack
                        direction="row"
                        spacing={1}
                        sx={{ mt: 2, flexWrap: 'wrap' }}
                        useFlexGap
                      >
                        {p.tags.map((t) => (
                          <Chip
                            key={t}
                            label={t}
                            size="small"
                            variant="outlined"
                          />
                        ))}
                      </Stack>
                    </CardContent>
                    <CardActions sx={{ px: 2, pb: 2 }}>
                      <Button
                        component={NextLink}
                        href={p.href}
                        variant="contained"
                      >
                        Open
                      </Button>
                    </CardActions>
                  </Card>
                </Grid>
              ))}
              {!isLoading && processes.length === 0 && (
                <Grid size={12}>
                  <Typography color="text.secondary">
                    You don't have access to any standard processes.
                  </Typography>
                </Grid>
              )}
            </Grid>
          </Stack>
        </Container>
      </Box>
    </>
  )
}

Page.getLayout = (page) => <DashboardLayout>{page}</DashboardLayout>

export default Page
