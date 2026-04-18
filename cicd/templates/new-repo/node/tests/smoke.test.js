import { test } from "node:test";
import assert from "node:assert/strict";
import { hello } from "../src/index.js";

test("smoke", () => {
    assert.equal(hello(), "hello from {{REPO_NAME}}");
});
