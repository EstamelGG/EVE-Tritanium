func industryActivityIconAsset(for activityID: Int) -> String {
    switch activityID {
    case 3: "Icon_ResearchTime"
    case 4: "Icon_ResearchMaterial"
    case 5: "Icon_Copying"
    case 8: "Icon_Invention"
    case 9, 11: "Icon_reaction"
    default: "Icon_Manufacturing"
    }
}
