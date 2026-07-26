"""Offline source-integrity tests for curated provider facts."""

import from datetime { datetime }
import from urllib.parse { urlparse }
import from provider_evidence {
    PROVIDER_EVIDENCE,
    provider_evidence_for
}


test "top provider evidence has one citation per SOC claim" {
    assert len(PROVIDER_EVIDENCE) == 15;
    for (domain, evidence) in PROVIDER_EVIDENCE.items() {
        assert evidence.domain == domain;
        assert evidence.soc2_status != "";
        source = urlparse(evidence.soc2_source_url);
        assert source.scheme == "https";
        assert source.hostname is not None;
        observed = datetime.fromisoformat(evidence.observed_at);
        assert observed.tzinfo is not None;
    }
}


test "uncited downtime remains absent" {
    for evidence in PROVIDER_EVIDENCE.values() {
        assert evidence.downtime_hours is None;
        assert evidence.downtime_source_urls == [];
    }
}


test "provider evidence resolves by domain or canonical name" {
    openai = provider_evidence_for(
        "www.openai.com",
        ""
    );
    assert openai is not None;
    assert openai.soc2_status == "soc2_type_ii";
    aws = provider_evidence_for(
        "",
        "Amazon Web Services, Inc."
    );
    assert aws is not None;
    assert aws.domain == "amazon.com";
    assert provider_evidence_for(
        "unknown.example",
        "Unknown"
    ) is None;
}
