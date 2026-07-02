# Política de Segurança

## Reportando uma vulnerabilidade

Se você encontrar uma vulnerabilidade de segurança neste projeto (por
exemplo, validação de URL insuficiente, path traversal na leitura/escrita de
`config.json`/`cameras.json`, ou algo que permita acesso indevido a streams),
por favor **não abra uma issue pública**.

Em vez disso, entre em contato diretamente com o mantenedor via GitHub
(perfil do repositório) descrevendo:

- Passos para reproduzir
- Impacto esperado
- Versão/commit afetado

Faremos o possível para responder e corrigir em tempo razoável.

## Escopo

Este é um app desktop local. As principais superfícies de risco são:

- URLs de câmeras (RTSP/HLS) fornecidas pelo usuário — validadas em
  `validar_url()` (`cameras_app/app.py`) para aceitar apenas esquemas
  `rtsp(s)://` e `http(s)://` com `.m3u8`.
- Arquivos de configuração locais (`config.json`, `cameras.json`), escritos
  atomicamente e nunca por `eval`/`exec`.

Uso responsável: acesse apenas streams para os quais você tem autorização
(veja a seção "Uso responsável" no [README](README.md)).
