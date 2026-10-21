import { describe, expect, test } from "bun:test";
import { awsClientConfig } from "../../src/actions/aws";
import { contextOf } from "./support";

describe("the AWS client configuration", () => {
  test("takes the region from cloud-providers.account and assumes the lambda role from identity-access-control, as legacy", async () => {
    const config = await awsClientConfig(
      contextOf({
        providers: {
          "cloud-providers": { account: { region: "eu-west-1" } },
          "identity-access-control": {
            iam_role_arns: { arns: [{ selector: "other", arn: "arn:aws:iam::1:role/x" }, { selector: "lambda", arn: "arn:aws:iam::1:role/np" }] },
          },
        },
      }),
    );
    expect(config.region).toBe("eu-west-1");
    expect(config.roleArn).toBe("arn:aws:iam::1:role/np");
    expect(typeof config.credentials).toBe("function");
  });

  test("falls back to the scope configuration's assume role", async () => {
    const config = await awsClientConfig(
      contextOf({ providers: { "scope-configurations": { assume_role: { arn: "arn:aws:iam::1:role/legacy" } } } }),
    );
    expect(config.roleArn).toBe("arn:aws:iam::1:role/legacy");
  });

  test("leaves the default credential chain and region when the platform names none", async () => {
    const config = await awsClientConfig(contextOf({ providers: {} }));
    expect(config).toEqual({ region: undefined, roleArn: undefined, credentials: undefined });
  });
});
