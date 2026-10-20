export default {
  resource: "admin.adminPlugins.show",
  path: "/plugins",
  map() {
    this.route("xgoose-overview", { path: "overview" });
    this.route("xgoose-users", { path: "users" });
    this.route("xgoose-user", { path: "users/:id" });
    this.route("xgoose-sessions", { path: "sessions" });
    this.route("xgoose-session", { path: "sessions/:id" });
  },
};
