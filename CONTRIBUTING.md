# Contribuindo com o vigia-cam

Obrigado pelo interesse em contribuir! Este é um projeto pequeno, então o
processo é simples.

## Ambiente de desenvolvimento

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt -r requirements-dev.txt
```

## Rodando os testes

```bash
pytest
```

## Lint / formatação

```bash
ruff check .
ruff format .
```

## Fluxo de contribuição

1. Abra uma *issue* descrevendo o bug ou a melhoria proposta.
2. Faça um fork e crie um branch a partir de `main`.
3. Garanta que `pytest` e `ruff check .` passam antes de abrir o PR.
4. Descreva no PR o que mudou e por quê.

## Convenções do código

- Nomes de funções/variáveis do domínio (UI, câmeras, config) em português,
  para consistência com o restante do app.
- Sem comentários explicando o "o quê" — só o "porquê" quando não for óbvio.
- Evite adicionar dependências novas sem necessidade clara.
