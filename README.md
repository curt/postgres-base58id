# postgres-base58id

PostgreSQL extension providing a native **base58id** data type: a 64-bit unsigned integer with automatic Base58 encoding for text I/O.

## Purpose

This is the **second of three related projects** for building and distributing PostgreSQL C extensions:

1. **postgres-dev-builder** - Builds and publishes cached toolchain images
2. **postgres-base58id** (this project) - Compiles C extensions and publishes versioned artifacts
3. **postgis-base58id-image** - Builds final runtime images by installing pre-compiled artifacts

## Why this exists

This project takes the C extension source code and:
- Compiles it for multiple architectures (amd64, arm64) using the dev images from project #1
- Packages the compiled binaries (`.so`, `.control`, `.sql` files) into versioned tar.gz archives
- Publishes these artifacts as GitHub Releases for consumption by runtime image builders (project #3)

This separates the compilation step from the runtime image, allowing:
- **Versioned artifacts**: Each release is independently downloadable
- **Multi-arch support**: Single release includes binaries for multiple architectures
- **Decoupled builds**: Runtime images can be rebuilt without recompiling
- **Matrix builds**: Support multiple PostgreSQL versions (15, 16, 17) and variants (alpine, bookworm)

## Features

- **Compact storage**: 8 bytes, pass-by-value (same as `bigint`)
- **Base58 encoding**: Bitcoin alphabet (no `0OIl` ambiguity), zero-padded to 11 characters
- **Full operator support**: Comparison operators (`<`, `<=`, `=`, `>=`, `>`, `<>`)
- **Indexable**: B-tree and hash operator classes included
- **Cast support**: Bidirectional casts with `bigint` and `text`
- **Binary I/O**: Efficient `COPY` and client protocol support
- **Uniform hash distribution**: Uses PostgreSQL's `hash_any()` for optimal hash index performance

## Project Structure

```
postgres-base58id/
├── extension/
│   ├── base58id.c              # C implementation (encoding, I/O, operators)
│   ├── base58id--1.0.sql       # SQL type/function definitions (shell type pattern)
│   ├── base58id.control        # Extension metadata
│   └── Makefile                # PGXS build rules
├── .github/workflows/
│   └── release.yml             # Multi-arch compilation and GitHub Releases
├── Makefile                    # Orchestrates compilation and packaging
└── README.md                   # This file
```

## Getting Started

### Prerequisites

1. **Docker** with buildx support
2. **Access to postgres-dev images** from project #1:
   - Either build locally: `cd ../postgres-dev-builder && make build-local`
   - Or use published images: `ghcr.io/yourorg/postgres-dev:17-alpine`

### Configuration

Update registry settings in [Makefile](Makefile):
```makefile
REGISTRY ?= ghcr.io/yourorg  # Change to your GitHub org/username
```

### Local Development

```bash
# Test compilation (single platform)
make test PG_MAJOR=17 VARIANT=alpine

# Compile for all platforms
make compile PG_MAJOR=17 VARIANT=alpine PLATFORMS=linux/arm64,linux/amd64

# Create release packages
make package PG_MAJOR=17 VARIANT=alpine

# Clean build artifacts
make clean
```

### Creating a Release

1. **Tag the release:**
   ```bash
   git tag -a v1.0.0 -m "Release version 1.0.0"
   git push origin v1.0.0
   ```

2. **GitHub Actions automatically:**
   - Compiles for all PostgreSQL versions (15, 16, 17)
   - Compiles for all variants (alpine, bookworm)
   - Compiles for all architectures (amd64, arm64)
   - Creates tar.gz archives for each combination
   - Publishes to GitHub Releases

3. **Download artifacts:**
   ```bash
   # Example release URLs:
   # base58id-1.0.0-pg17-alpine-arm64.tar.gz
   # base58id-1.0.0-pg17-alpine-amd64.tar.gz
   # base58id-1.0.0-pg17-bookworm-arm64.tar.gz
   # ... etc
   ```

## Makefile Targets

| Target     | Description                                           |
|------------|-------------------------------------------------------|
| `compile`  | Compile extension for specified platforms             |
| `package`  | Create tar.gz release archives                        |
| `test`     | Test compilation in dev container                     |
| `all`      | Compile and package (default)                         |
| `clean`    | Remove dist/ and releases/ directories                |

## Usage Example

```sql
-- Enable the extension
CREATE EXTENSION base58id;

-- Create a table with base58id primary key
CREATE TABLE events (
    id base58id PRIMARY KEY,
    payload jsonb
);

-- Insert a Snowflake-style ID (zero-padded to 11 characters)
INSERT INTO events VALUES ('1111MKNMDHF', '{"event": "user.login"}');

-- Query by ID
SELECT * FROM events WHERE id = '1111MKNMDHF';

-- Cast to/from bigint
SELECT '1111MKNMDHF'::base58id::bigint;  -- 987654321
SELECT 987654321::bigint::base58id;       -- '1111MKNMDHF'
SELECT 0::bigint::base58id;               -- '11111111111'
```

## Architecture Decisions

1. **Why separate compilation from runtime images?**
   - Faster iteration: Rebuild runtime images without recompiling
   - Versioned artifacts: Pin to specific extension versions
   - Smaller runtime images: No build tools needed

2. **Why matrix builds?**
   - Support multiple PostgreSQL versions simultaneously
   - Support both Debian (bookworm) and Alpine variants
   - Enable users to choose their preferred base image

3. **Why GitHub Releases?**
   - Permanent, versioned storage for binaries
   - Easy downloading via URLs in Dockerfiles
   - Automatic changelog generation

4. **Why tar.gz instead of .deb/.rpm?**
   - Simpler cross-platform support
   - Direct `tar -xzf` in Dockerfiles
   - Works with both Alpine (apk) and Debian (apt)

## Initial Setup

1. **Initialize git repository:**
   ```bash
   cd /path/to/postgres-base58id
   git init
   git add .
   git commit -m "Initial commit: base58id extension"
   ```

2. **Test local build:**
   ```bash
   make test PG_MAJOR=17 VARIANT=alpine
   ```

3. **Create GitHub repository and push:**
   ```bash
   git remote add origin git@github.com:yourorg/postgres-base58id.git
   git push -u origin main
   ```

4. **Create first release:**
   ```bash
   git tag -a v1.0.0 -m "Initial release"
   git push origin v1.0.0
   ```

5. **Verify GitHub Actions:**
   - Check Actions tab for workflow execution
   - Check Releases section for published artifacts

## Extension Implementation Notes

### Shell Type Pattern

The SQL file ([extension/base58id--1.0.sql](extension/base58id--1.0.sql)) uses the "shell type" pattern required by PostgreSQL:

1. Create shell type: `CREATE TYPE base58id;`
2. Define I/O functions that reference the shell type
3. Complete type definition with I/O functions

This order is critical - the I/O functions (`base58id_in`, `base58id_out`, etc.) must exist before the full `CREATE TYPE` statement.

### Hash Distribution

For time-based IDs (Snowflake/Sonyflake), the hash function uses PostgreSQL's `hash_any()` to ensure uniform distribution despite monotonic values. See [extension/base58id.c](extension/base58id.c) for implementation.

## Project History

Originally part of a monolithic `postgis-base58id` project that mixed:
- Building PostGIS base images from source
- Building dev toolchain images
- Compiling C extensions
- Building final runtime images

Split into three focused projects (Oct 2025) to enable:
- Independent versioning of extension code
- Reusable compilation artifacts
- Faster iteration on runtime images

## Next Steps

After setting up this project:
1. Ensure **postgres-dev-builder** images are available in your registry
2. Create a release tag to trigger artifact builds
3. Use the published artifacts in **postgis-base58id-image** (project #3)

## Author

**Curt Gilman**

## License

MIT License - see [LICENSE](LICENSE) for details
