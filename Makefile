.PHONY: install install-dev run lint test

install:
	python3 -m venv .venv
	.venv/bin/pip install -q -r requirements.txt

install-dev: install
	.venv/bin/pip install -q -r requirements-dev.txt

run:
	.venv/bin/python cameras_app/app.py

lint:
	.venv/bin/ruff check .

test:
	.venv/bin/pytest -q
