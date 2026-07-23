import js from '@eslint/js';
import tseslint from 'typescript-eslint';
import globals from 'globals';

export default tseslint.config(
  {
    // The native clients are built by their own toolchains; their build directories
    // contain vendored third-party JS that has nothing to do with this repo's lint rules.
    ignores: [
      '**/dist/**',
      '**/src/gen/**',
      '**/node_modules/**',
      '**/.turbo/**',
      'clients/macos/.build/**',
      'clients/android/**/build/**',
    ],
  },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    files: ['**/*.ts', '**/*.mjs'],
    languageOptions: {
      globals: { ...globals.node },
    },
  },
);
