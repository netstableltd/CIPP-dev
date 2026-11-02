import {
  Box,
  Chip,
  FormControl,
  FormControlLabel,
  FormLabel,
  Radio,
  RadioGroup,
  Stack,
  Typography,
} from '@mui/material'
import { Controller } from 'react-hook-form'

/** Pros and cons of the chosen option, so the effect of a choice is in front of whoever makes it. */
const Effects = ({ option }) =>
  option ? (
    <Box sx={{ mt: 0.5, pl: 4 }}>
      <Typography variant="body2" color="text.secondary">
        {option.summary}
      </Typography>
      <Box component="ul" sx={{ m: 0, mt: 0.5, pl: 2.5 }}>
        {(option.pros ?? []).map((p) => (
          <Typography
            component="li"
            variant="body2"
            key={`p-${p}`}
            sx={{ color: 'success.main' }}
          >
            {p}
          </Typography>
        ))}
        {(option.cons ?? []).map((c) => (
          <Typography
            component="li"
            variant="body2"
            key={`c-${c}`}
            sx={{ color: 'warning.main' }}
          >
            {c}
          </Typography>
        ))}
      </Box>
    </Box>
  ) : null

/**
 * The customer's choices for the shared mailbox: one radio group per question in the add-on's question
 * set, with our recommendation marked and the chosen option's effects shown. Values live in the form at
 * answers.<questionId>; `current` (from an existing mailbox) marks what it has now.
 */
export const CippSharedMailboxChoices = ({
  formControl,
  questions = [],
  current = {},
  children = {},
}) => (
  <Stack spacing={2.5}>
    {questions.map((q, i) => (
      <Controller
        key={q.id}
        name={`answers.${q.id}`}
        control={formControl.control}
        render={({ field }) => {
          const chosen = q.options.find((o) => o.id === field.value)
          return (
            <FormControl component="fieldset">
              <FormLabel
                component="legend"
                sx={{ fontWeight: 600, color: 'text.primary' }}
              >
                {i + 1}. {q.question}
              </FormLabel>
              <RadioGroup
                row
                value={field.value ?? ''}
                onChange={(e) => field.onChange(e.target.value)}
                aria-label={q.title}
              >
                {q.options.map((o) => (
                  <FormControlLabel
                    key={o.id}
                    value={o.id}
                    control={<Radio size="small" />}
                    label={
                      <Stack
                        direction="row"
                        spacing={0.75}
                        alignItems="center"
                        useFlexGap
                        sx={{ flexWrap: 'wrap' }}
                      >
                        <span>{o.label}</span>
                        {o.recommended && (
                          <Chip
                            size="small"
                            color="success"
                            variant="outlined"
                            label="Recommended"
                          />
                        )}
                        {current?.[q.id] === o.id && (
                          <Chip size="small" variant="outlined" label="Now" />
                        )}
                      </Stack>
                    }
                  />
                ))}
              </RadioGroup>
              <Effects option={chosen} />
              {children[q.id] && (
                <Box sx={{ mt: 1, pl: 4 }}>{children[q.id](field.value)}</Box>
              )}
            </FormControl>
          )
        }}
      />
    ))}
  </Stack>
)

export default CippSharedMailboxChoices
