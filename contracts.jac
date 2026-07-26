"""Frozen shared types (spec 11.2). Field changes are a conversation, not a commit."""

obj DetectedVendor {
    has domain: str;
    has name: str;
    has method: str = "";      # dns | headers | scripts | manual
}

obj SubprocessorRecord {
    has name: str;
    has purpose: str = "";
    has hosting_region: str = "";
}

obj ResolvedSubprocessor {
    has canonical_name: str;
    has purpose: str = "";
    has region: str = "";
    has confidence: float = 1.0;
}

obj RiskHeadline {
    has biggest_risk: str;
    has biggest_suggestion: str;
}
