{
  description = "Human-in-the-Loop RAG Agent Development Environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs @ { flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];

      perSystem = { system, ... }:
        let
          pkgs = import inputs.nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
        in
        {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            # Python prerequisites
            python312
            uv

            # Node.js prerequisites
            nodejs_22

            # Database prerequisites
            (postgresql_16.withPackages (p: [ p.pgvector ]))
          ];

          shellHook = ''
            echo "Fetching OPENAI_API_KEY from 1Password..."
            export OPENAI_API_KEY=$(op.exe item get OpenAI --fields key --reveal)
            if [ -n "$OPENAI_API_KEY" ]; then
                echo "OPENAI_API_KEY set successfully."
            else
                echo "Warning: Failed to retrieve OPENAI_API_KEY from 1Password."
            fi

            # Postgres Setup
            export PGDATA=$PWD/.postgres
            export PGHOST=$PWD/.postgres
            export PG_PASS_FILE=$PWD/.pg_password
            
            # Generate password if missing
            if [ ! -f "$PG_PASS_FILE" ]; then
                echo "Generating random database password..."
                python3 -c "import secrets; print(secrets.token_urlsafe(16))" > $PG_PASS_FILE
            fi
            
            export DB_PASS=$(cat $PG_PASS_FILE)
            export PGPASSWORD=$DB_PASS
            
            if [ ! -f "$PGDATA/PG_VERSION" ]; then
              echo "Initializing PostgreSQL data directory..."
              # Remove directory if it exists but is empty or corrupt to ensure clean init
              rm -rf $PGDATA
              # Initialize with the generated password
              initdb -D $PGDATA -U user --auth=md5 --pwfile=$PG_PASS_FILE
              
              # Config for TCP
              echo "listen_addresses = '*'" >> $PGDATA/postgresql.conf
              echo "port = 5432" >> $PGDATA/postgresql.conf
              echo "unix_socket_directories = '$PGDATA'" >> $PGDATA/postgresql.conf
            fi
            
            # Start if not running
            if ! pg_ctl status -D $PGDATA >/dev/null; then
              echo "Starting PostgreSQL..."
              pg_ctl start -D $PGDATA -l $PGDATA/logfile -o "-k $PGDATA"
              
              # Loop wait for postgres to be ready
              echo "Waiting for PostgreSQL to start..."
              for i in {1..10}; do
                if pg_isready -h localhost -p 5432 >/dev/null 2>&1; then
                  echo "PostgreSQL is ready."
                  break
                fi
                sleep 1
              done
            fi
            
            # Create DB if needed
            if pg_isready -h localhost -p 5432 >/dev/null 2>&1; then
                if ! psql -h localhost -U user -lqt | cut -d \| -f 1 | grep -qw rag_db; then
                  echo "Creating database rag_db..."
                  createdb -h localhost -U user rag_db
                fi
            else 
                echo "Warning: PostgreSQL failed to start. Check $PGDATA/logfile."
            fi

            # Setup local environment variables for dev convenience
            export LLM_API_KEY=$OPENAI_API_KEY
            export LLM_MODEL=gpt-4o-mini
            export LLM_BASE_URL=https://api.openai.com/v1
            export DATABASE_URL="postgresql://user:$DB_PASS@localhost:5432/rag_db"
            export AGENT_URL="http://localhost:8000"
          '';
        };
      };
    };
}
