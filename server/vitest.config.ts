import { generateKeyPairSync } from "node:crypto";
import path from "node:path";
import { cloudflareTest, readD1Migrations } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";

// Clé de signature éphémère, propre aux tests.
const { privateKey, publicKey } = generateKeyPairSync("ed25519");
const pkcs8 = privateKey.export({ format: "der", type: "pkcs8" }).toString("base64");
const rawPublic = (publicKey.export({ format: "der", type: "spki" }) as Buffer).subarray(12).toString("base64");

const migrations = await readD1Migrations(path.join(import.meta.dirname, "migrations"));

export default defineConfig({
  plugins: [
    cloudflareTest({
      wrangler: { configPath: "./wrangler.jsonc" },
      miniflare: {
        bindings: {
          TEST_MIGRATIONS: migrations,
          PUBLIC_BASE_URL: "https://verif.test",
          SIGNING_KEY_ID: "test1",
          SIGNING_PRIVATE_KEY: pkcs8,
          SIGNING_PUBLIC_KEYS: JSON.stringify([{ keyId: "test1", publicKey: rawPublic }]),
          PAYMENT_WEBHOOK_SECRET: "whsec_test",
          IP_HASH_SECRET: "ip_test",
          PAYMENT_PRODUCTS: JSON.stringify({ "111": "single", "222": "pro" }),
          MIN_APP_VERSION: "1.0.0",
        },
      },
    }),
  ],
  test: {
    setupFiles: ["./test/apply-migrations.ts"],
  },
});
