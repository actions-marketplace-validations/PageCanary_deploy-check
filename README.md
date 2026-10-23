# PageCanary deploy check

After every deploy, PageCanary's AI agent walks your site's main flow (signup, booking, checkout or contact form) in a real browser, like a customer, and fails the check if it broke. The job summary shows what it did and links the recording.

It never sends a form, creates an account, books or pays: it stops at the last step. If PageCanary itself can't run the check, the step warns and passes, so it never blocks a deploy for our sake.

## Use it with Vercel

1. Make an API key at https://www.pagecanary.com/dashboard/api and add it to the repository's secrets as `PAGECANARY_API_KEY`.
2. For previews behind Vercel's deployment protection, turn on **Protection Bypass for Automation** in the Vercel project and add the secret as `VERCEL_AUTOMATION_BYPASS_SECRET`. It's sent only to the deployment's own host and never stored.
3. Add the workflow:

```yaml
# .github/workflows/pagecanary.yml
name: PageCanary deploy check
on: deployment_status
jobs:
  walk:
    if: github.event.deployment_status.state == 'success'
    runs-on: ubuntu-latest
    steps:
      - uses: pagecanary/deploy-check@v1
        with:
          api-key: ${{ secrets.PAGECANARY_API_KEY }}
          vercel-bypass-secret: ${{ secrets.VERCEL_AUTOMATION_BYPASS_SECRET }}
```

Anywhere else, pass `url:` and run it after your deploy step.

## Inputs

| Input | Default | |
|---|---|---|
| `api-key` | required | PageCanary API key |
| `url` | the deployment's URL (`deployment_status` events) | Site to walk |
| `vercel-bypass-secret` | | For protected Vercel previews |
| `test-plan` | none | Steps in plain English, one per line, to walk instead of the main flow |
| `fail-on` | `failed` | `never` to report without failing |
| `timeout-minutes` | `6` | How long to wait |
| `api-base` | `https://www.pagecanary.com` | PageCanary's API |

## Your own steps

```yaml
      - uses: pagecanary/deploy-check@v1
        with:
          api-key: ${{ secrets.PAGECANARY_API_KEY }}
          test-plan: |
            Open the pricing page
            Choose the Starter plan
            Check the checkout shows $10 a month
```

Each step passes only when the agent sees it happen on the page, and the job summary shows every step's result. It still never pays, creates an account, sends personal details or leaves your site.

## Outputs

`result` (`passed`, `failed`, `cant-test`, `planned`, or `error`), `headline`, `recording-url`, `walk-id`.

## Limits

Free during the beta: 10 walks a day per PageCanary account, shared by all of its API keys. A deploy over the limit gets a warning in the job summary and passes.

## How it works

`check.sh` starts a walk (`POST /api/v1/walks`), polls it (`GET /api/v1/walks/:id`) every few seconds, writes the job summary and sets the outputs. It needs only `curl` and `jq`, both on GitHub's hosted runners. API docs: https://www.pagecanary.com/docs/api

Made by n34t, LLC.
