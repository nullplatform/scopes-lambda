/**
 * The scope's name in the account's zone, as the legacy Route53 setup names it:
 * `<ns>-<app>-<scope>.<account>.<zone>`, in the public zone for public functions and the private
 * zone otherwise. The name is known before the exposure (the load balancer rule matches it); the
 * record exists only behind a load balancer — an API Gateway endpoint serves its own host and
 * would need a custom domain to answer to a name, which no legacy workflow created either.
 */
import * as aws from "@pulumi/aws";
import type * as pulumi from "@pulumi/pulumi";
import type { ScopeProgramContext } from "@nullplatform/plugin/program";
import { attributesOf, providersOf } from "./context";
import type { HttpExposure } from "./http";
import type { Names } from "./names";

const TTL_SECONDS = 60;

export interface DnsName {
  zoneId?: string;
  /** The fully qualified name, when the account has a zone for this visibility. */
  fqdn?: pulumi.Output<string>;
}

export interface Dns {
  record?: aws.route53.Record;
  domain: pulumi.Output<string> | string;
}

export function dnsName(ctx: ScopeProgramContext, names: Names, opts: pulumi.ResourceOptions = {}): DnsName {
  const attributes = attributesOf(ctx);
  const networking = providersOf(ctx).cloud.networking ?? {};
  const zoneId = attributes.visibility === "private" ? networking.hosted_zone_id : networking.hosted_public_zone_id;
  if (!zoneId) return {};
  const zone = aws.route53.getZoneOutput({ zoneId }, opts);
  return { zoneId, fqdn: zone.name.apply((name) => `${names.dnsName}.${name.replace(/\.$/, "")}`) };
}

export function dns(names: Names, name: DnsName, exposure: HttpExposure, opts: pulumi.ResourceOptions = {}): Dns {
  if (exposure.kind !== "alb" || !name.zoneId || !name.fqdn) return { domain: "" };
  const record = new aws.route53.Record(
    `${names.dnsName}-cname`,
    { zoneId: name.zoneId, name: name.fqdn, type: "CNAME", ttl: TTL_SECONDS, records: [exposure.dnsTarget] },
    opts,
  );
  return { record, domain: name.fqdn };
}
