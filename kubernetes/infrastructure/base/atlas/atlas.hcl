# Placeholder
env "local" {
  src = "postgres://postgres:scratch@localhost:5433/postgres?sslmode=disable"
  dev = "docker://postgres/16/dev"
  migration {
    dir = "file://migrations"
  }
}