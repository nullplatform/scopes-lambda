import { describe, expect, test } from "bun:test";
import { awsClientConfig } from "../../src/actions/aws";
import { contextOf } from "./support";

describe("the AWS client configuration", () => {
  test("takes the region from cloud-providers and assumes the lambda role from aws-iam-configuration", async () => {
    const config = await awsClientConfig(
      contextOf({
        providers: {
          "cloud-providers": { region: "eu-west-1" },
          "aws-iam-configuration": { arns: { lambda: "arn:aws:iam::1:role/np" } },
        },
      }),
    );
    expect(config.region).toBe("eu-west-1");
    expect(config.roleArn).toBe("arn:aws:iam::1:role/np");
    expect(typeof config.credentials).toBe("function");
  });

  test("leaves the default credential chain and region when the platform names none", async () => {
    const config = await awsClientConfig(contextOf({ providers: {} }));
    expect(config).toEqual({ region: undefined, roleArn: undefined, credentials: undefined });
  });
});
