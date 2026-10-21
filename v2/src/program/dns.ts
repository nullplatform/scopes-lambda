/**
 * The scope's name in the account's zone: a CNAME to the load balancer or the API endpoint, in
 * the public zone for public functions and the private zone otherwise.
 */
import * as aws from "@pulumi/aws";
import type * as pulumi from "@pulumi/pulumi";
import type { ScopeProgramContext } from "@nullplatform/plugin/program";
import { attributesOf, providersOf } from "./context";
import type { HttpExposure } from "./http";
import type { Names } from "./names";

const TTL_SECONDS = 60;

export interface Dns {
  record?: aws.route53.Record;
  domain?: string;
}

export function dns(ctx: ScopeProgramContext, names: Names, exposure: HttpExposure, opts: pulumi.ResourceOptions = {}): Dns {
  if (exposure.kind === "none") return {};
  const attributes = attributesOf(ctx);
  const networking = providersOf(ctx).cloud.networking ?? {};
  const zoneId = attributes.visibility === "private" ? networking.hosted_zone_id : networking.hosted_public_zone_id;
  if (!zoneId) return {};
  const zone = aws.route53.getZoneOutput({ zoneId }, opts);
  const domain = ctx.naming.dns(names.dnsName);
  const record = new aws.route53.Record(
    `${names.dnsName}-cname`,
    {
      zoneId,
      name: zone.name.apply((name) => `${domain}.${name.replace(/\.$/, "")}`),
      type: "CNAME",
      ttl: TTL_SECONDS,
      records: [exposure.dnsTarget],
    },
    opts,
  );
  return { record, domain };
}
