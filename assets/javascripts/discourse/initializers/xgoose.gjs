import { apiInitializer } from "discourse/lib/api";
import XgoosePanel from "../components/xgoose-panel";
export default apiInitializer((api) => {
  if (api.container.lookup("service:site-settings").xgoose_enabled) {
    api.renderInOutlet("below-footer", XgoosePanel);
  }
});
