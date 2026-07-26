test "registry contains 150 verified companies" {
    assert registry_size() == 150;
}


test "registry resolves a known company" {
    stripe = resolve_registry("stripe.com");
    assert stripe is not None;
    assert stripe.name == "Stripe";
    assert stripe.subprocessor_url.startswith("https://");
}


test "registry normalizes the www prefix" {
    cloudflare = resolve_registry("www.cloudflare.com");
    assert cloudflare is not None;
    assert cloudflare.name == "Cloudflare";
}


test "registry returns none for an unknown company" {
    assert resolve_registry("not-in-the-registry.example") is None;
}


test "every registry key matches its entry domain" {
    for (domain, entry) in VENDOR_REGISTRY.items() {
        assert domain == entry.domain;
        assert entry.subprocessor_url.startswith("https://");
        assert entry.source_type in {
            "official_website",
            "official_github"
        };
    }
}
