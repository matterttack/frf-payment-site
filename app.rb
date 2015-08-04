require 'rubygems'
require 'sinatra'
require 'securerandom'
require 'json'

require 'prius'
require 'gocardless_pro'
require 'i18n'
require 'i18n/backend/fallbacks'
require 'rack'
require 'rack/contrib'
require 'net/http'

# Load Environment Variables
Prius.load(:gocardless_token)
Prius.load(:gc_api_key_secret)
Prius.load(:gc_creditor_id)

PACKAGE_PRICES = {
  "standard" => { "GBP" => 15, "EUR" => 19 },
  "concession" => { "GBP" => 5, "EUR" => 7 },
}

# Internationalisation by browser preference
use Rack::Locale

# Settings
set :session_secret, 'fredrochefoundationsecret2015'
set :api_client, GoCardlessPro::Client.new(
  access_token: Prius.get(:gocardless_token)
)

# Configuration
configure do
  I18n::Backend::Simple.send(:include, I18n::Backend::Fallbacks)
  I18n.load_path = Dir[File.join(settings.root, 'locales', '*.yml')]
  I18n.backend.load_translations
  I18n.config.enforce_available_locales = false
  I18n.default_locale = :en
end

# Enable sessions and before every request, make sure visitors have been assigned a
# session ID.
enable :sessions
before { session[:token] ||= SecureRandom.uuid }

# Customer visits the site. Hi Customer!
get '/' do
  @prices = {}

  PACKAGE_PRICES.each do |package, pricing_hash|
    @prices[package.to_sym] = case I18n.locale
                              when :fr then "€#{pricing_hash["EUR"]}"
                              else "£#{pricing_hash["GBP"]}"
                              end
  end

  erb :index
end

# Customer purchases an item
post '/purchase' do

# Get the package from params
package = params[:package]

# Generate a success URL. This is where GC will send the customer after they've paid.
uri = URI.parse(request.env["REQUEST_URI"])
success_url = "#{uri.scheme}://#{uri.host}#{":#{uri.port}" unless [80, 443].include?(uri.port)}/payment_complete?package=#{package}"

# Create a redirect_flow
redirect_flow = settings.api_client.redirect_flows.create(
  params: {
    description: I18n.t(:package_description, package: package.capitalize),
    session_token: session[:token],
    success_redirect_url: success_url,
    scheme: params[:scheme],
    links: {
      creditor: Prius.get(:gc_creditor_id)
      }
    }
  )

# Follow redirect flow
redirect redirect_flow.redirect_url
end


# Customer returns from GC's payment pages
get '/payment_complete' do
  package = params[:package]
  redirect_flow_id = params[:redirect_flow_id]
  price = PACKAGE_PRICES.fetch(package)

  # Complete the redirect flow
  puts session[:token]
  puts redirect_flow_id

  # Create customer, customer bank account and mandate
  completed_redirect_flow = settings.api_client.redirect_flows.
    complete(redirect_flow_id, params: { session_token: session[:token] }
    )

  mandate = settings.api_client.mandates.get(completed_redirect_flow.links.mandate)

  # Create the subscription
  currency = case mandate.scheme
             when "bacs" then "GBP"
             when "sepa_core" then "EUR"
             end

  subscription = settings.api_client.subscriptions.create(
    params: {
      amount: price[currency] * 100, # Price in pence/cents
      currency: currency,
      name: I18n.t(:package_description, package: package.capitalize),
      interval_unit: "yearly",
      metadata: {
        order_no: SecureRandom.uuid # Could be anything
      },
      links: {
        mandate: mandate.id
      }
    }
  )

# Redirect to /thankyou
  redirect "/thankyou?package=#{package}&subscription_id=#{subscription.id}"
end

get '/thankyou' do
  package = params[:package]
  subscription = settings.api_client.subscriptions.get(params[:subscription_id])
  currency = subscription.currency

  currency_symbol = case currency
                    when "GBP" then "£"
                    when "EUR" then "€"
                    end
  @price = "#{currency_symbol}#{"%.2f" % PACKAGE_PRICES[package][currency]}"
  @first_payment_date = subscription.upcoming_payments.first['charge_date']
  @package = package

  erb :thankyou
end
