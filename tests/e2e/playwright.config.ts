import { defineConfig, devices } from "@playwright/test";

/**
 * Playwright config — Story 06.26 E2E smoke (Lab Inter RAG).
 *
 * Usa Chrome do usuário com perfil persistido (login MSAL Apex Mercado tenant
 * já feito uma vez, cookies salvos). Quando rodar, NÃO precisa logar de novo
 * — Easy Auth foi disabled (commit 27f2cc3) e MSAL pega session do cache do
 * Chrome.
 *
 * IMPORTANTE: feche o Chrome ANTES de rodar (profile in use causa erro).
 * Se quiser rodar com Chrome aberto, mude userDataDir pra cópia temporária.
 */

const FRONTEND_URI =
  process.env.FRONTEND_URI ||
  "https://app-helpsphere-helpsphere-saas.azurewebsites.net";
const USER_DATA_DIR =
  process.env.CHROME_USER_DATA_DIR ||
  "C:\\Users\\GuilhermePruxCampos\\AppData\\Local\\Google\\Chrome\\User Data\\E2E-Profile";

export default defineConfig({
  testDir: ".",
  timeout: 90_000,
  expect: { timeout: 15_000 },
  fullyParallel: false,
  workers: 1,
  reporter: [["list"], ["html", { open: "never" }]],
  use: {
    baseURL: FRONTEND_URI,
    trace: "on",
    screenshot: "on",
    video: "retain-on-failure",
    headless: false,
    viewport: { width: 1440, height: 900 },
  },
  projects: [
    {
      name: "chrome-user-profile",
      use: {
        ...devices["Desktop Chrome"],
        channel: "chrome",
        launchOptions: {
          args: [
            `--user-data-dir=${USER_DATA_DIR}`,
            "--no-first-run",
            "--no-default-browser-check",
          ],
        },
      },
    },
  ],
});
