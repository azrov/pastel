// Formatting Pascal files with "pastel fmt --stdin": Format Document,
// Shift+Alt+F, and format on save.
import * as path from 'path';
import * as vscode from 'vscode';
import { runPastel } from './cli';

/** The formatted text, or an error message when the code could not be read. */
export async function formatText(text: string, fileName: string): Promise<{ text?: string; error?: string }> {
  const result = await runPastel(['fmt', '--stdin', fileName], path.dirname(fileName), text);
  if (result.code === 0) {
    return { text: result.stdout };
  }
  return { error: (result.stderr || result.stdout).trim() || 'pastel fmt failed' };
}

export function registerFormatter(context: vscode.ExtensionContext): void {
  const provider: vscode.DocumentFormattingEditProvider = {
    async provideDocumentFormattingEdits(document) {
      const original = document.getText();
      const formatted = await formatText(original, document.fileName);
      if (formatted.error !== undefined) {
        // not a pop-up: format on save would show it while the code is half typed
        vscode.window.setStatusBarMessage(`$(warning) Pastel could not format: ${formatted.error}`, 8000);
        return [];
      }
      if (formatted.text === undefined || formatted.text === original) {
        return [];
      }
      const end = document.lineAt(document.lineCount - 1).range.end;
      return [vscode.TextEdit.replace(new vscode.Range(new vscode.Position(0, 0), end), formatted.text)];
    },
  };
  context.subscriptions.push(
    vscode.languages.registerDocumentFormattingEditProvider(
      [{ language: 'pascal' }, { language: 'objectpascal' }], provider));
}
