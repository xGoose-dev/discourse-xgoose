import DiscourseRoute from "discourse/routes/discourse";
export default class extends DiscourseRoute {
  model(params) {
    return params;
  }
}
