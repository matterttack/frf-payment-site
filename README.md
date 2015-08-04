# Fred Roche Foundation subscription app

This is an ammended version of the GoCardless Pro Ruby example to work with the new API.

The app passes details to the GoCardless api to retrieve a redirect flow, and set up customers with mandates
to pay the Fred Roche Foundation for their annual friends programme.

## Running the app locally

```
git clone git@github.com:matterttack/frf-payment-site.git
cd frf-payment-site
bundle install

export GC_ACCESS_TOKEN=...
export GC_CREDITOR_ID=...
export GC_ENVIRONMENT=...
bundle exec shotgun app.rb
```
