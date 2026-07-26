"""Cited provider facts. Empty fields are intentional: no citation, no claim."""

import from contracts { ProviderEvidence }
import from atlas_seed {
    normalize_company_identity,
    normalize_domain
}


glob PROVIDER_EVIDENCE: dict[str, ProviderEvidence] = {
    "amazon.com": ProviderEvidence(
        domain="amazon.com",
        name="Amazon Web Services",
        soc2_status="soc2_type_ii",
        soc2_source_url="https://aws.amazon.com/compliance/soc-faqs/",
        observed_at="2026-07-26T00:00:00-07:00"
    ),
    "anthropic.com": ProviderEvidence(
        domain="anthropic.com",
        name="Anthropic",
        soc2_status="soc2_type_ii",
        soc2_source_url="https://privacy.anthropic.com/en/articles/10015870-what-certifications-has-anthropic-obtained",
        observed_at="2026-07-26T00:00:00-07:00"
    ),
    "cloudflare.com": ProviderEvidence(
        domain="cloudflare.com",
        name="Cloudflare",
        soc2_status="soc2_type_ii",
        soc2_source_url="https://www.cloudflare.com/en-gb/trust-hub/compliance-resources/soc-2/",
        observed_at="2026-07-26T00:00:00-07:00"
    ),
    "datadoghq.com": ProviderEvidence(
        domain="datadoghq.com",
        name="Datadog",
        soc2_status="soc2_type_ii",
        soc2_source_url="https://trust.datadoghq.com/",
        observed_at="2026-07-26T00:00:00-07:00"
    ),
    "fivetran.com": ProviderEvidence(
        domain="fivetran.com",
        name="Fivetran",
        soc2_status="soc2_type_ii",
        soc2_source_url="https://fivetran.com/docs/activations/misc/security-and-privacy",
        observed_at="2026-07-26T00:00:00-07:00"
    ),
    "github.com": ProviderEvidence(
        domain="github.com",
        name="GitHub",
        soc2_status="soc2_attested",
        soc2_source_url="https://github.com/security",
        observed_at="2026-07-26T00:00:00-07:00"
    ),
    "google.com": ProviderEvidence(
        domain="google.com",
        name="Google Cloud",
        soc2_status="soc2_type_ii",
        soc2_source_url="https://cloud.google.com/security/compliance/soc-2",
        observed_at="2026-07-26T00:00:00-07:00"
    ),
    "intercom.com": ProviderEvidence(
        domain="intercom.com",
        name="Intercom",
        soc2_status="soc2_type_ii",
        soc2_source_url="https://www.intercom.com/help/en/articles/7053674-accessing-security-and-compliance-documents",
        observed_at="2026-07-26T00:00:00-07:00"
    ),
    "microsoft.com": ProviderEvidence(
        domain="microsoft.com",
        name="Microsoft Azure",
        soc2_status="soc2_type_ii",
        soc2_source_url="https://learn.microsoft.com/en-us/compliance/regulatory/offering-soc-2",
        observed_at="2026-07-26T00:00:00-07:00"
    ),
    "openai.com": ProviderEvidence(
        domain="openai.com",
        name="OpenAI",
        soc2_status="soc2_type_ii",
        soc2_source_url="https://openai.com/security-and-privacy/",
        observed_at="2026-07-26T00:00:00-07:00"
    ),
    "salesforce.com": ProviderEvidence(
        domain="salesforce.com",
        name="Salesforce",
        soc2_status="soc_reports_available",
        soc2_source_url="https://help.salesforce.com/s/articleView?id=000382043&language=en_US&type=1",
        observed_at="2026-07-26T00:00:00-07:00"
    ),
    "snowflake.com": ProviderEvidence(
        domain="snowflake.com",
        name="Snowflake",
        soc2_status="soc2_type_ii",
        soc2_source_url="https://docs.snowflake.com/en/user-guide/cert-soc-2",
        observed_at="2026-07-26T00:00:00-07:00"
    ),
    "stripe.com": ProviderEvidence(
        domain="stripe.com",
        name="Stripe",
        soc2_status="soc2_type_ii",
        soc2_source_url="https://support.stripe.com/questions/download-soc-reports?locale=en-GB",
        observed_at="2026-07-26T00:00:00-07:00"
    ),
    "twilio.com": ProviderEvidence(
        domain="twilio.com",
        name="Twilio",
        soc2_status="soc2_type_ii",
        soc2_source_url="https://www.twilio.com/en-us/legal/security-overview",
        observed_at="2026-07-26T00:00:00-07:00"
    ),
    "zendesk.com": ProviderEvidence(
        domain="zendesk.com",
        name="Zendesk",
        soc2_status="soc2_type_ii",
        soc2_source_url="https://www.zendesk.com/trust-center/",
        observed_at="2026-07-26T00:00:00-07:00"
    )
};


def provider_evidence_for(
    domain: str,
    name: str
) -> ProviderEvidence | None {
    normalized_domain: str = normalize_domain(domain);
    if normalized_domain in PROVIDER_EVIDENCE {
        return PROVIDER_EVIDENCE[normalized_domain];
    }
    identity: str = normalize_company_identity(name);
    for evidence in PROVIDER_EVIDENCE.values() {
        if normalize_company_identity(evidence.name) == identity {
            return evidence;
        }
    }
    return None;
}
