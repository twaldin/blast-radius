"""Validate the complete committed Atlas seed corpus."""

import from atlas_seed { load_seed_directory }


with entry {
    (validated_seeds, validation_errors) = load_seed_directory();
    if validation_errors {
        for validation_error in validation_errors {
            print(validation_error);
        }
        raise SystemExit(1);
    }
    print(f"Validated {len(validated_seeds)} atlas seeds");
}
