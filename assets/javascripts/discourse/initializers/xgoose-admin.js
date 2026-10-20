import { apiInitializer } from "discourse/lib/api";
export default apiInitializer((api) => {
  if (!api.container.lookup("service:current-user")?.admin) return;
  api.setAdminPluginIcon("discourse-xgoose", "discourse-sparkles");
  api.addAdminPluginConfigurationNav("discourse-xgoose", [
    {
      label: "xgoose.admin.overview",
      route: "adminPlugins.show.xgoose-overview",
      description: "xgoose.admin.description",
    },
    {
      label: "xgoose.admin.users",
      route: "adminPlugins.show.xgoose-users",
      description: "xgoose.admin.users_description",
    },
    {
      label: "xgoose.admin.sessions",
      route: "adminPlugins.show.xgoose-sessions",
      description: "xgoose.admin.sessions_description",
    },
  ]);
});
