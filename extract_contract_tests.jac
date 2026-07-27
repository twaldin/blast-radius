"""Offline contract test for the typed byLLM extraction boundary."""

import from jaclang.byllm.lib { MockLLM }
import from extract {
    ExtractionRecord,
    normalize_extraction_records
}


glob test_extractor = MockLLM(
    model_name="mockllm",
    config={
        "outputs": [[
            ExtractionRecord(
                name="  Amazon   Web Services  ",
                purpose=" Cloud   hosting ",
                hosting_region=" United States "
            )
        ]]
    }
);


def mock_extract_records(
    page_text: str
) -> list[ExtractionRecord] by test_extractor();


test "byllm extraction contract returns typed records" {
    records: list[ExtractionRecord] = mock_extract_records(
        "Current subprocessors include AWS."
    );
    normalized = normalize_extraction_records(records);
    assert len(normalized) == 1;
    assert normalized[0].name == "Amazon Web Services";
    assert normalized[0].purpose == "Cloud hosting";
    assert normalized[0].hosting_region == "United States";
}
