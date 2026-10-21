import { definePackage } from "@nullplatform/plugin/package";
import manifest from "../package.json" with { type: "json" };
import { lambda } from "./resources";

export default definePackage({
  name: manifest.name,
  version: manifest.version,
  description: manifest.description,
  components: [lambda],
});
