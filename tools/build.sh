#!/bin/sh
# Gera Elementistas.exe na raiz do projeto (preset "Windows Desktop").
# Uso: sh tools/build.sh   — também roda sozinho após cada commit (gancho post-commit).
cd "$(dirname "$0")/.." || exit 1

GODOT="$(command -v godot_console || command -v godot)"
if [ -z "$GODOT" ]; then
	for candidate in "$LOCALAPPDATA"/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_*/Godot_v*_win64_console.exe; do
		[ -f "$candidate" ] && GODOT="$candidate"
	done
fi
if [ -z "$GODOT" ]; then
	echo "Godot não encontrado. Instale com: winget install GodotEngine.GodotEngine" >&2
	exit 1
fi

# Exporta para um arquivo temporário e troca no fim: se o jogo estiver aberto
# (exe em uso), o antigo continua funcionando e o erro é avisado.
"$GODOT" --headless --path . --export-release "Windows Desktop" Elementistas.new.exe > tools/last_build.log 2>&1
if [ ! -f Elementistas.new.exe ]; then
	echo "Falha na exportação; veja tools/last_build.log" >&2
	exit 1
fi
if mv -f Elementistas.new.exe Elementistas.exe 2>/dev/null; then
	echo "Elementistas.exe atualizado."
else
	echo "Não deu para substituir Elementistas.exe (o jogo está aberto?). Nova versão em Elementistas.new.exe" >&2
	exit 1
fi
