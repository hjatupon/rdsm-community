.PHONY: build run logs stop shell

# Build the image
build:
	docker compose build

# Start simulation (foreground — Ctrl-C to stop)
run:
	docker compose up

# Start in background
up:
	docker compose up -d

# Tail logs from running container
logs:
	docker compose logs -f

# Stop and remove container
stop:
	docker compose down

# Open a shell inside the running container for debugging
shell:
	docker compose exec sim bash

# Build + run in one step
start: build run
