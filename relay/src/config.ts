import { readFileSync } from "node:fs";

export interface SalesforceConfig {
  loginUrl: string;
  clientId: string;
  username: string;
  privateKey: string;
  apiVersion: string;
}

export interface Config {
  port: number;
  relayApiToken: string | undefined;
  ring: {
    apiBase: string;
    accessToken: string | undefined;
    webhookSecret: string | undefined;
    pollIntervalSeconds: number;
  };
  /** Undefined when Salesforce isn't configured; events are then only logged. */
  salesforce: SalesforceConfig | undefined;
}

function optional(env: NodeJS.ProcessEnv, key: string): string | undefined {
  const value = env[key]?.trim();
  return value ? value : undefined;
}

function loadPrivateKey(env: NodeJS.ProcessEnv): string | undefined {
  const inline = optional(env, "SF_PRIVATE_KEY");
  if (inline) return inline.replace(/\\n/g, "\n");
  const path = optional(env, "SF_PRIVATE_KEY_PATH");
  return path ? readFileSync(path, "utf8") : undefined;
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const clientId = optional(env, "SF_CLIENT_ID");
  const username = optional(env, "SF_USERNAME");
  const privateKey = loadPrivateKey(env);

  const sfFields = [clientId, username, privateKey];
  if (sfFields.some(Boolean) && !sfFields.every(Boolean)) {
    throw new Error("Salesforce config is partial: set SF_CLIENT_ID, SF_USERNAME and SF_PRIVATE_KEY(_PATH) together");
  }

  return {
    port: Number(env.PORT ?? 3000),
    relayApiToken: optional(env, "RELAY_API_TOKEN"),
    ring: {
      apiBase: optional(env, "RING_API_BASE") ?? "https://api.amazonvision.com",
      accessToken: optional(env, "RING_ACCESS_TOKEN"),
      webhookSecret: optional(env, "RING_WEBHOOK_SECRET"),
      pollIntervalSeconds: Number(env.RING_POLL_INTERVAL_SECONDS ?? 0),
    },
    salesforce:
      clientId && username && privateKey
        ? {
            loginUrl: optional(env, "SF_LOGIN_URL") ?? "https://login.salesforce.com",
            clientId,
            username,
            privateKey,
            apiVersion: optional(env, "SF_API_VERSION") ?? "62.0",
          }
        : undefined,
  };
}
